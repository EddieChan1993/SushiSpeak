import SwiftUI
import AVFoundation

// MARK: - Main View

struct ContentView: View {
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var whisper = WhisperTranscriber()
    @AppStorage("lastMinutes") private var selectedMinutes = 5
    @AppStorage("lastSeconds") private var selectedSeconds = 0
    @AppStorage("audioFormat") private var audioFormatRaw = AudioFormat.mp3.rawValue
    @AppStorage("whisperModel") private var whisperModelRaw = WhisperModel.small.rawValue
    @State private var timeRemaining = 0
    @State private var isRunning = false
    @State private var timerTask: Task<Void, Never>?
    @State private var startHovered = false
    @State private var showDeleteConfirm = false
    @State private var showModelPicker = false

    var selectedFormat: AudioFormat {
        AudioFormat(rawValue: audioFormatRaw) ?? .mp3
    }

    var selectedWhisperModel: WhisperModel {
        WhisperModel(rawValue: whisperModelRaw) ?? .small
    }

    var totalSeconds: Int { selectedMinutes * 60 + selectedSeconds }

    var timeDisplay: String {
        String(format: "%02d:%02d", timeRemaining / 60, timeRemaining % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            timerPanel
            Divider()
            recordingsPanel
        }
        .frame(minWidth: 360, minHeight: 520)
        .onAppear {
            timeRemaining = totalSeconds
            recorder.preferredFormat = selectedFormat
        }
        .onChange(of: audioFormatRaw) { _ in
            recorder.preferredFormat = selectedFormat
        }
        .onDisappear {
            timerTask?.cancel()
            if isRunning { recorder.stopRecording() }
        }
    }

    // MARK: Header

    var headerBar: some View {
        HStack(spacing: 8) {
            Text("🍣")
                .font(.title2)
            Text("SushiSpeak")
                .font(.title2.weight(.semibold))
            Spacer()
            if isRunning {
                RecordingBadge()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Timer Panel

    var timerPanel: some View {
        VStack(spacing: 18) {
            Text(timeDisplay)
                .font(.system(size: 88, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(isRunning ? Color.red : Color.primary)
                .animation(.easeInOut(duration: 0.3), value: isRunning)
                .padding(.top, 24)

            ZStack {
                WaveformView(level: recorder.audioLevel)
                    .padding(.horizontal, 24)
                    .opacity(isRunning ? 1 : 0)

                HStack(spacing: 10) {
                    Text("Duration:")
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedMinutes) {
                        ForEach(0..<60, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                    .onChange(of: selectedMinutes) { _ in
                        timeRemaining = totalSeconds
                    }

                    Picker("", selection: $selectedSeconds) {
                        ForEach(0..<60, id: \.self) {
                            Text(String(format: "%02d sec", $0)).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .onChange(of: selectedSeconds) { _ in
                        timeRemaining = totalSeconds
                    }

                    Divider().frame(height: 20)

                    Picker("", selection: $audioFormatRaw) {
                        ForEach(AudioFormat.allCases, id: \.rawValue) {
                            Text($0.rawValue).tag($0.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 64)
                }
                .opacity(isRunning ? 0 : 1)
                .disabled(isRunning)
                .allowsHitTesting(!isRunning)
            }
            .frame(height: 48)
            .animation(.easeInOut(duration: 0.2), value: isRunning)

            Button(action: toggleSession) {
                Label(
                    isRunning ? "Stop" : "Start",
                    systemImage: isRunning ? "stop.circle.fill" : "play.circle.fill"
                )
                .frame(width: 130, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .tint(isRunning ? .red : .accentColor)
            .controlSize(.large)
            .scaleEffect(startHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: startHovered)
            .onHover { startHovered = $0 }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Recordings Panel

    var recordingsPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Recordings")
                    .font(.headline)
                Text("(\(recorder.recordings.count))")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                Spacer()

                // Whisper model picker + download status
                if let progress = whisper.downloadProgress {
                    HStack(spacing: 6) {
                        ProgressView(value: progress)
                            .frame(width: 60)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button { whisper.cancelDownload() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $whisperModelRaw) {
                            ForEach(WhisperModel.allCases) { m in
                                HStack {
                                    Text(m.shortName)
                                    if !whisper.isModelAvailable(m) {
                                        Image(systemName: "arrow.down.circle")
                                    }
                                }.tag(m.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                        .onChange(of: whisperModelRaw) { _ in
                            if !whisper.isModelAvailable(selectedWhisperModel) {
                                whisper.downloadModel(selectedWhisperModel)
                            }
                        }

                        if !whisper.isModelAvailable(selectedWhisperModel) {
                            Button {
                                whisper.downloadModel(selectedWhisperModel)
                            } label: {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("Download \(selectedWhisperModel.displayName)")
                        }
                    }
                }

                if !recorder.recordings.isEmpty {
                    Divider().frame(height: 16)
                    Button("Delete All") { showDeleteConfirm = true }
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                        .confirmationDialog(
                            "Delete all \(recorder.recordings.count) recordings?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Delete All", role: .destructive) { recorder.deleteAll() }
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            if recorder.recordings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No recordings yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(recorder.recordings) { rec in
                        RecordingRow(
                            recording: rec,
                            whisper: whisper,
                            whisperModel: selectedWhisperModel,
                            onDelete: { recorder.delete(rec) }
                        )
                        .listRowInsets(EdgeInsets())
                        .id(rec.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: recorder.recordings.first?.id) { _ in
                        if let first = recorder.recordings.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    func toggleSession() {
        if isRunning { stopSession() } else { startSession() }
    }

    func startSession() {
        guard totalSeconds > 0 else { return }
        timeRemaining = totalSeconds
        isRunning = true
        recorder.startRecording()

        let duration = totalSeconds
        timerTask = Task { @MainActor in
            for _ in 0..<duration {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                timeRemaining -= 1
            }
            guard !Task.isCancelled else { return }
            stopSession()
            sendCompletionNotification()
        }
    }

    func sendCompletionNotification() {
        // Play system alert sound
        NSSound(named: NSSound.Name("Glass"))?.play()
        // Bounce dock icon until user clicks the app
        NSApp.requestUserAttention(.criticalRequest)
    }

    func stopSession() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
        recorder.stopRecording()
        timeRemaining = totalSeconds
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let level: Float
    private let startDate = Date()

    private let barCount = 28

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red.opacity(0.7 + 0.3 * Double(level)))
                        .frame(width: 3, height: barHeight(index: i, elapsed: elapsed))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 48)
    }

    private func barHeight(index: Int, elapsed: Double) -> CGFloat {
        let amp = CGFloat(level)
        let speed = 2.2 + Double(index % 5) * 0.3
        let wave = sin(elapsed * speed + Double(index) * 0.65) * 0.5 + 0.5
        return max(2, amp * 42 * wave + 2)
    }
}

// MARK: - Recording Badge

struct RecordingBadge: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
                .opacity(pulsing ? 0.3 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: pulsing
                )
            Text("REC")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        }
        .onAppear { pulsing = true }
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    let recording: Recording
    let whisper: WhisperTranscriber
    let whisperModel: WhisperModel
    let onDelete: () -> Void

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var isHovered = false
    @State private var folderHovered = false
    @State private var transcribeHovered = false
    @State private var transcribeState: TranscribeState = .idle
    @State private var deleteHovered = false
    @State private var showDeleteConfirm = false

    enum TranscribeState {
        case idle, loading, done, failed
    }

    var formatBadgeColor: Color {
        switch recording.url.pathExtension.lowercased() {
        case "mp3": return .blue
        case "m4a": return .purple
        case "wav": return .green
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { togglePlay() } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isPlaying ? Color.orange : Color.accentColor)
                    .scaleEffect(isPlaying ? 1.1 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPlaying)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(recording.formattedDate)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 4) {
                    Text(recording.formattedDuration)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(recording.url.pathExtension.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(formatBadgeColor.opacity(0.15))
                        .foregroundStyle(formatBadgeColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            Spacer()

            Button { revealInFinder() } label: {
                Image(systemName: "folder")
                    .foregroundStyle(folderHovered ? Color.accentColor : Color.secondary)
                    .scaleEffect(folderHovered ? 1.15 : 1.0)
                    .animation(.spring(response: 0.15), value: folderHovered)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            .onHover { folderHovered = $0 }

            Button { transcribeAndCopy() } label: {
                Group {
                    switch transcribeState {
                    case .idle:
                        Image(systemName: "waveform.and.mic")
                    case .loading:
                        ProgressView().controlSize(.mini)
                    case .done:
                        Image(systemName: "checkmark")
                    case .failed:
                        Image(systemName: "xmark")
                    }
                }
                .foregroundStyle(
                    transcribeState == .done ? Color.green :
                    transcribeState == .failed ? Color.red :
                    transcribeHovered ? Color.accentColor : Color.secondary
                )
                .scaleEffect(transcribeHovered ? 1.15 : 1.0)
                .animation(.spring(response: 0.15), value: transcribeHovered)
                .animation(.spring(response: 0.15), value: transcribeState)
                .frame(width: 16)
            }
            .buttonStyle(.plain)
            .help("Transcribe and copy text to clipboard")
            .onHover { transcribeHovered = $0 }
            .disabled(transcribeState == .loading)

            Button { showDeleteConfirm = true } label: {
                Image(systemName: "trash")
                    .foregroundStyle(deleteHovered ? Color.red : Color.secondary)
                    .scaleEffect(deleteHovered ? 1.15 : 1.0)
                    .animation(.spring(response: 0.15), value: deleteHovered)
            }
            .buttonStyle(.plain)
            .onHover { deleteHovered = $0 }
            .confirmationDialog("Delete \"\(recording.formattedDate)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        .onHover { isHovered = $0 }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
    }

    func transcribeAndCopy() {
        transcribeState = .loading
        Task {
            do {
                let text = try await whisper.transcribe(url: recording.url, model: whisperModel)
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    transcribeState = .done
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { transcribeState = .idle }
                }
            } catch {
                await MainActor.run {
                    transcribeState = .failed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { transcribeState = .idle }
                }
                print("Transcribe error: \(error.localizedDescription)")
            }
        }
    }

    func togglePlay() {
        if isPlaying {
            player?.stop()
            isPlaying = false
        } else {
            guard let p = try? AVAudioPlayer(contentsOf: recording.url) else { return }
            player = p
            p.play()
            isPlaying = true
            DispatchQueue.main.asyncAfter(deadline: .now() + recording.duration + 0.5) {
                isPlaying = false
            }
        }
    }
}
