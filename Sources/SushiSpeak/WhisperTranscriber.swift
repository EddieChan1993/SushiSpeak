import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny   = "tiny"
    case base   = "base"
    case small  = "small"
    case medium = "medium"
    case large  = "large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny:   return "Tiny (~75 MB)"
        case .base:   return "Base (~142 MB)"
        case .small:  return "Small (~466 MB)"
        case .medium: return "Medium (~1.5 GB)"
        case .large:  return "Large V3 (~3.1 GB)"
        }
    }

    var shortName: String { rawValue.capitalized }

    var fileName: String { "ggml-\(rawValue).bin" }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }
}

class WhisperTranscriber: ObservableObject {
    @Published var downloadProgress: Double? = nil  // nil = idle
    @Published var downloadingModel: WhisperModel? = nil

    private var downloadTask: Task<Void, Error>? = nil

    // MARK: - Paths

    private var modelsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SushiSpeak/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func modelPath(for model: WhisperModel) -> URL {
        modelsDir.appendingPathComponent(model.fileName)
    }

    func isModelAvailable(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model).path)
    }

    private var execDir: String? {
        Bundle.main.executableURL?.deletingLastPathComponent().path
    }

    private var whisperPath: String? {
        if let dir = execDir {
            let p = (dir as NSString).appendingPathComponent("whisper-cli")
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        for p in ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"] {
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    private var ffmpegPath: String? {
        if let dir = execDir {
            let p = (dir as NSString).appendingPathComponent("ffmpeg")
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"] {
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    // MARK: - Download

    func downloadModel(_ model: WhisperModel) {
        downloadTask?.cancel()
        downloadTask = Task { @MainActor in
            downloadingModel = model
            downloadProgress = 0
            do {
                let dest = modelPath(for: model)
                let tmp = dest.appendingPathExtension("part")

                let (asyncBytes, response) = try await URLSession.shared.bytes(from: model.downloadURL)
                let total = (response as? HTTPURLResponse)?.expectedContentLength ?? -1

                guard let stream = OutputStream(url: tmp, append: false) else {
                    throw WhisperError.downloadFailed
                }
                stream.open()
                var buf = [UInt8]()
                buf.reserveCapacity(131_072)
                var received: Int64 = 0

                for try await byte in asyncBytes {
                    buf.append(byte)
                    if buf.count >= 131_072 {
                        let written = buf.count
                        buf.withUnsafeBytes { ptr in
                            _ = stream.write(ptr.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: written)
                        }
                        received += Int64(written)
                        buf.removeAll(keepingCapacity: true)
                        if total > 0 {
                            downloadProgress = Double(received) / Double(total)
                        }
                    }
                    try Task.checkCancellation()
                }
                if !buf.isEmpty {
                    buf.withUnsafeBytes { ptr in
                        _ = stream.write(ptr.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: buf.count)
                    }
                }
                stream.close()

                try FileManager.default.moveItem(at: tmp, to: dest)
            } catch is CancellationError {
                // silently cancelled
            } catch {
                print("Whisper download error: \(error)")
            }
            downloadProgress = nil
            downloadingModel = nil
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        DispatchQueue.main.async {
            self.downloadProgress = nil
            self.downloadingModel = nil
        }
    }

    func importModel(_ model: WhisperModel, from sourceURL: URL) throws {
        let dest = modelPath(for: model)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
    }

    // MARK: - Transcribe

    func transcribe(url: URL, model: WhisperModel, prompt: String? = nil) async throws -> String {
        guard let whisper = whisperPath else { throw WhisperError.binaryNotFound }
        let modelFile = modelPath(for: model)
        guard FileManager.default.fileExists(atPath: modelFile.path) else {
            throw WhisperError.modelNotDownloaded(model)
        }

        // whisper-cli natively supports mp3/flac/ogg/wav — no conversion needed
        // but convert to 16kHz mono wav for best accuracy
        let wavURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        if let ffmpeg = ffmpegPath {
            let conv = Process()
            conv.executableURL = URL(fileURLWithPath: ffmpeg)
            conv.arguments = ["-y", "-i", url.path,
                              "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
                              wavURL.path]
            conv.standardOutput = FileHandle.nullDevice
            conv.standardError  = FileHandle.nullDevice
            try conv.run(); conv.waitUntilExit()
        }

        let inputPath = FileManager.default.fileExists(atPath: wavURL.path) ? wavURL.path : url.path

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: whisper)

        var args = [
            "-m", modelFile.path,
            "-f", inputPath,
            "-l", "auto",
            "--no-timestamps",
            "-t", "\(max(1, ProcessInfo.processInfo.processorCount / 2))"
        ]
        if let prompt, !prompt.isEmpty {
            args += ["--prompt", prompt]
        }
        proc.arguments = args

        // Point backend search to bundled dylibs/plugins when running from app bundle
        var env = ProcessInfo.processInfo.environment
        if let dir = execDir {
            env["GGML_BACKEND_PATH"] = dir
            env["DYLD_LIBRARY_PATH"] = "\(dir):\(env["DYLD_LIBRARY_PATH"] ?? "")"
        }
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError  = errPipe

        try proc.run()
        proc.waitUntilExit()

        let raw = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // Filter any residual timestamp lines like [HH:MM:SS.mmm --> ...]
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("[") && !$0.isEmpty }
        let result = lines.joined(separator: " ")

        if result.isEmpty { throw WhisperError.emptyResult }
        return result
    }

    // MARK: - Error

    enum WhisperError: LocalizedError {
        case binaryNotFound
        case modelNotDownloaded(WhisperModel)
        case downloadFailed
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "whisper-cli not found. Install: brew install whisper-cpp"
            case .modelNotDownloaded(let m):
                return "Model \"\(m.shortName)\" not downloaded yet."
            case .downloadFailed:
                return "Failed to create download stream."
            case .emptyResult:
                return "Transcription returned no text."
            }
        }
    }
}
