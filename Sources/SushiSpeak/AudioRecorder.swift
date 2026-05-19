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

        // Try MP3 first (requires macOS built-in Fraunhofer encoder)
        let mp3URL = storageDir.appendingPathComponent("rec_\(ts).mp3")
        if let f = try? AVAudioFile(forWriting: mp3URL, settings: [
            AVFormatIDKey: kAudioFormatMPEGLayer3,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000
        ]) { return (f, mp3URL) }

        // Fallback: M4A (AAC)
        let m4aURL = storageDir.appendingPathComponent("rec_\(ts).m4a")
        if let f = try? AVAudioFile(forWriting: m4aURL, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]) { return (f, m4aURL) }

        return nil
    }

    private func doStart() {
        let eng = AVAudioEngine()
        let input = eng.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let (file, url) = makeAudioFile(sampleRate: inputFormat.sampleRate) else { return }
        audioFile = file
        currentURL = url

        // Boost input gain before writing to file
        let boosterNode = AVAudioMixerNode()
        eng.attach(boosterNode)
        eng.connect(input, to: boosterNode, format: inputFormat)
        eng.connect(boosterNode, to: eng.mainMixerNode, format: inputFormat)
        boosterNode.outputVolume = 2.5
        eng.mainMixerNode.outputVolume = 0  // no speaker bleed

        let tapFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 1)!

        boosterNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)

            // RMS metering
            guard let data = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(max(count, 1)))
            let level: Float = rms > 0.012 ? min(1, (rms - 0.012) * 14) : 0
            // exponential smoothing — avoids frame-rate stuttering
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

        guard let url = currentURL else { return }
        let duration = Date().timeIntervalSince(startTime ?? Date())
        recordings.insert(
            Recording(id: UUID(), url: url, date: startTime ?? Date(), duration: duration),
            at: 0
        )
        currentURL = nil
        startTime = nil
    }

    func duplicate(_ recording: Recording) {
        let dest = storageDir.appendingPathComponent("rec_\(Int(Date().timeIntervalSince1970)).m4a")
        guard (try? FileManager.default.copyItem(at: recording.url, to: dest)) != nil else { return }
        let copy = Recording(id: UUID(), url: dest, date: Date(), duration: recording.duration)
        recordings.insert(copy, at: 0)
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
        for url in files.filter({ ["m4a", "mp3", "wav"].contains($0.pathExtension) }) {
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
