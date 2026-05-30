// Copyright © 2026 EddieChan1993. All rights reserved.
// Unauthorized commercial use is strictly prohibited.

import Foundation
import AVFoundation
import CoreMedia

enum AudioFormat: String, CaseIterable {
    case mp3 = "MP3"
    case m4a = "M4A"
    case wav = "WAV"

    var fileExtension: String { rawValue.lowercased() }
    var color: String {
        switch self {
        case .mp3: return "blue"
        case .m4a: return "purple"
        case .wav: return "green"
        }
    }
}

class AudioRecorder: NSObject, ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var audioLevel: Float = 0

    var preferredFormat: AudioFormat = .mp3

    private var engine: AVAudioEngine?
    private var booster: AVAudioMixerNode?
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var startTime: Date?

    private var ffmpegPath: String? {
        if let execURL = Bundle.main.executableURL {
            let bundled = execURL.deletingLastPathComponent().appendingPathComponent("ffmpeg").path
            if FileManager.default.fileExists(atPath: bundled) { return bundled }
        }
        return ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    private var storageDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SushiSpeak/recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override init() {
        super.init()
        migrateFromDocumentsIfNeeded()
        Task { await loadRecordings() }
    }

    /// 把旧版存在 ~/Documents/SushiSpeak/ 的录音迁移到 Application Support
    private func migrateFromDocumentsIfNeeded() {
        let oldBase = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let oldDir = oldBase.appendingPathComponent("SushiSpeak")
        guard FileManager.default.fileExists(atPath: oldDir.path) else { return }
        let exts = Set(["m4a", "mp3", "aac", "wav"])
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: oldDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }
        let audioFiles = files.filter { exts.contains($0.pathExtension.lowercased()) }
        guard !audioFiles.isEmpty else { return }
        let dest = storageDir
        for src in audioFiles {
            let target = dest.appendingPathComponent(src.lastPathComponent)
            if !FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.moveItem(at: src, to: target)
            }
        }
    }

    func startRecording(onStarted: @escaping () -> Void = {}) {
        // If already authorized, start synchronously to avoid async delay skewing the timer
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            doStart()
            onStarted()
        } else {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard granted, let self else { return }
                DispatchQueue.main.async {
                    self.doStart()
                    onStarted()
                }
            }
        }
    }

    private func makeAudioFile(sampleRate: Double) -> (AVAudioFile, URL)? {
        let ts = Int(Date().timeIntervalSince1970)
        // Always record as M4A; convert to target format after stopping
        let url = storageDir.appendingPathComponent("rec_\(ts).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        guard let f = try? AVAudioFile(forWriting: url, settings: settings) else { return nil }
        return (f, url)
    }

    private func doStart() {
        let eng = AVAudioEngine()
        let input = eng.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let (file, url) = makeAudioFile(sampleRate: inputFormat.sampleRate) else { return }
        audioFile = file
        currentURL = url

        let boosterNode = AVAudioMixerNode()
        eng.attach(boosterNode)
        eng.connect(input, to: boosterNode, format: inputFormat)
        eng.connect(boosterNode, to: eng.mainMixerNode, format: inputFormat)
        boosterNode.outputVolume = 2.5
        eng.mainMixerNode.outputVolume = 0

        let tapFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 1)!
        boosterNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
            guard let data = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(max(count, 1)))
            let level: Float = rms > 0.012 ? min(1, (rms - 0.012) * 14) : 0
            DispatchQueue.main.async {
                guard let self else { return }
                self.audioLevel = self.audioLevel * 0.55 + level * 0.45
            }
        }

        do {
            eng.prepare()
            try eng.start()
            engine = eng
            booster = boosterNode
            startTime = Date()
        } catch {
            print("AVAudioEngine error: \(error)")
        }
    }

    func stopRecording() {
        audioLevel = 0
        booster?.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        booster = nil
        audioFile = nil

        guard let sourceURL = currentURL else { return }
        let date = startTime ?? Date()
        let duration = Date().timeIntervalSince(date)
        currentURL = nil
        startTime = nil

        let targetFormat = preferredFormat
        Task {
            let finalURL = await convert(from: sourceURL, to: targetFormat)
            let rec = Recording(id: UUID(), url: finalURL, date: date, duration: duration)
            await MainActor.run { recordings.insert(rec, at: 0) }
        }
    }

    // MARK: - Format conversion via bundled/system ffmpeg

    private func convert(from sourceURL: URL, to format: AudioFormat) async -> URL {
        if format == .m4a { return sourceURL }

        guard let ffmpeg = ffmpegPath else { return sourceURL }

        let outURL = sourceURL.deletingPathExtension().appendingPathExtension(format.fileExtension)
        var args = ["-y", "-i", sourceURL.path]
        if format == .mp3 { args += ["-q:a", "2"] }
        args.append(outURL.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               FileManager.default.fileExists(atPath: outURL.path) {
                try? FileManager.default.removeItem(at: sourceURL)
                return outURL
            }
        } catch {}

        return sourceURL
    }


    func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.url)
        recordings.removeAll { $0.id == recording.id }
    }

    func deleteAll() {
        recordings.forEach { try? FileManager.default.removeItem(at: $0.url) }
        recordings.removeAll()
    }

    private func loadRecordings() async {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storageDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        var result: [Recording] = []
        for url in files.filter({ ["m4a", "mp3", "aac", "wav"].contains($0.pathExtension) }) {
            let attrs = try? url.resourceValues(forKeys: [.creationDateKey])
            let date = attrs?.creationDate ?? Date()
            let asset = AVURLAsset(url: url)
            let cmDuration = (try? await asset.load(.duration)) ?? .zero
            let dur = CMTimeGetSeconds(cmDuration)
            result.append(Recording(id: UUID(), url: url, date: date, duration: max(dur, 0)))
        }
        let sorted = result.sorted { $0.date > $1.date }
        await MainActor.run { recordings = sorted }
    }
}