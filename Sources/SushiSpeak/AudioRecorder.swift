import Foundation
import AVFoundation
import CoreMedia

class AudioRecorder: NSObject, ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var audioLevel: Float = 0

    private var engine: AVAudioEngine?
    private var booster: AVAudioMixerNode?
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var startTime: Date?

    private var storageDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SushiSpeak", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override init() {
        super.init()
        Task { await loadRecordings() }
    }

    func startRecording() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted, let self else { return }
            DispatchQueue.main.async { self.doStart() }
        }
    }

    private func makeAudioFile(sampleRate: Double) -> (AVAudioFile, URL)? {
        let ts = Int(Date().timeIntervalSince1970)
        // Record as M4A (reliable), convert to MP3 after stopping
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

        // Try to convert M4A → MP3 in background
        Task {
            let finalURL = await convertToMP3(from: sourceURL)
            let rec = Recording(id: UUID(), url: finalURL, date: date, duration: duration)
            await MainActor.run { recordings.insert(rec, at: 0) }
        }
    }

    // MARK: - MP3 conversion via lame or ffmpeg

    private func convertToMP3(from sourceURL: URL) async -> URL {
        let mp3URL = sourceURL.deletingPathExtension().appendingPathExtension("mp3")

        let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        guard let ffmpeg = ffmpegPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return sourceURL // ffmpeg not found, keep M4A
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        proc.arguments = ["-y", "-i", sourceURL.path, "-q:a", "2", mp3URL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               FileManager.default.fileExists(atPath: mp3URL.path) {
                try? FileManager.default.removeItem(at: sourceURL)
                return mp3URL
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
