import SwiftUI
import AVFoundation

// MARK: - Audio Player

class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var currentRecording: Recording?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var scrollTargetID: UUID? = nil
    @Published var volume: Float = 0.3 {
        didSet { player?.volume = volume }
    }

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ recording: Recording) {
        if currentRecording?.id == recording.id {
            if isPlaying { pause() } else { resume() }
        } else {
            play(recording)
        }
    }

    func play(_ recording: Recording) {
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: recording.url) else { return }
        player = p
        p.delegate = self
        p.prepareToPlay()
        p.volume = volume
        duration = p.duration
        currentRecording = recording
        p.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func resume() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        timer?.invalidate()
        timer = nil
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let p = self.player else { return }
            DispatchQueue.main.async { self.currentTime = p.currentTime }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = self.duration
            self.timer?.invalidate()
        }
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var whisper = WhisperTranscriber()
    @StateObject private var audioPlayer = AudioPlayer()
    @AppStorage("lastMinutes") private var selectedMinutes = 5
    @AppStorage("lastSeconds") private var selectedSeconds = 0
    @AppStorage("audioFormat") private var audioFormatRaw = AudioFormat.mp3.rawValue
    @AppStorage("whisperModel") private var whisperModelRaw = WhisperModel.small.rawValue
    @State private var timeRemaining = 0
    @State private var isRunning = false
    @State private var timerTask: Task<Void, Never>?
    @AppStorage("hideTimer") private var hideTimer = false
    @State private var startHovered = false
    @State private var showDeleteConfirm = false
    @State private var importHovered = false
    @State private var linkHovered = false
    @State private var importErrorMsg: String? = nil
    @State private var showImportError = false
    @State private var isValidatingImport = false
    @State private var showModelInfo = false
    @State private var deleteModelHovered = false
    @State private var showDeleteModelConfirm = false

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
        .frame(minWidth: 380, minHeight: 620)
        .background(WindowTitleHider())
        .onAppear {
            timeRemaining = totalSeconds
            recorder.preferredFormat = selectedFormat
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
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
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .cornerRadius(5)
            Text("SushiSpeak")
                .font(.title2.weight(.semibold))
            Spacer()
            modelPickerControls
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    var modelPickerControls: some View {
        HStack(spacing: 6) {
            Button { showModelInfo = true } label: {
                Image(systemName: "globe")
                    .foregroundStyle(linkHovered ? Color.accentColor : Color.secondary)
                    .scaleEffect(linkHovered ? 1.15 : 1.0)
                    .animation(.spring(response: 0.15), value: linkHovered)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("查看下载地址")
            .onHover { linkHovered = $0 }
            .popover(isPresented: $showModelInfo, arrowEdge: .bottom) {
                ModelInfoPopover(model: selectedWhisperModel, isPresented: $showModelInfo)
            }

            Picker("", selection: $whisperModelRaw) {
                ForEach(WhisperModel.allCases) { m in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(whisper.isModelAvailable(m) ? Color.green : Color.clear)
                            .frame(width: 6, height: 6)
                        Text(m.shortName)
                    }.tag(m.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 100)
            .focusable(false)

            if isValidatingImport {
                ProgressView().controlSize(.small).help("正在验证模型…")
            } else if !whisper.isModelAvailable(selectedWhisperModel) {
                Button { importModelFile() } label: {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(importHovered ? Color.accentColor : Color.secondary)
                        .scaleEffect(importHovered ? 1.15 : 1.0)
                        .animation(.spring(response: 0.15), value: importHovered)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("导入 ggml-\(selectedWhisperModel.rawValue).bin")
                .onHover { importHovered = $0 }
            } else {
                Button { showDeleteModelConfirm = true } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(deleteModelHovered ? Color.red : Color.secondary)
                        .scaleEffect(deleteModelHovered ? 1.15 : 1.0)
                        .animation(.spring(response: 0.15), value: deleteModelHovered)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("删除 \(selectedWhisperModel.shortName) 模型文件")
                .onHover { deleteModelHovered = $0 }
                .confirmationDialog(
                    "删除 \(selectedWhisperModel.shortName) 模型？",
                    isPresented: $showDeleteModelConfirm,
                    titleVisibility: .visible
                ) {
                    Button("删除", role: .destructive) {
                        try? whisper.deleteModel(selectedWhisperModel)
                    }
                } message: {
                    Text("模型文件将从本地删除，下次使用需重新导入。")
                }
            }
        }
        .alert("导入失败", isPresented: $showImportError) {
            Button("好") {}
        } message: { Text(importErrorMsg ?? "") }
    }

    // MARK: Timer Panel

    var timerPanel: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .trailing) {
                Text(hideTimer ? "--:--" : timeDisplay)
                    .font(.system(size: 88, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(isRunning ? Color.red : Color.primary)
                    .animation(.easeInOut(duration: 0.3), value: isRunning)
                    .animation(.easeInOut(duration: 0.2), value: hideTimer)
                    .frame(maxWidth: .infinity)

                Button { hideTimer.toggle() } label: {
                    Image(systemName: hideTimer ? "eye.slash" : "eye")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(hideTimer ? "显示倒计时" : "隐藏倒计时")
                .padding(.trailing, 24)
            }
            .padding(.top, 24)

            ZStack {
                WaveformView(level: recorder.audioLevel)
                    .padding(.horizontal, 24)
                    .opacity(isRunning ? 1 : 0)

                HStack(spacing: 10) {
                    Text("Duration:")
                        .foregroundStyle(.secondary)

                    Stepper(
                        value: $selectedMinutes, in: 0...59,
                        onEditingChanged: { _ in timeRemaining = totalSeconds }
                    ) {
                        Text("\(selectedMinutes) min")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    .onChange(of: selectedMinutes) { _ in timeRemaining = totalSeconds }
                    .focusable(false)

                    Stepper(
                        value: $selectedSeconds, in: 0...59,
                        onEditingChanged: { _ in timeRemaining = totalSeconds }
                    ) {
                        Text(String(format: "%02d sec", selectedSeconds))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                    .onChange(of: selectedSeconds) { _ in timeRemaining = totalSeconds }
                    .focusable(false)

                    Divider().frame(height: 20)

                    Picker("", selection: $audioFormatRaw) {
                        ForEach(AudioFormat.allCases, id: \.rawValue) {
                            Text($0.rawValue).tag($0.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 64)
                    .focusable(false)
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
            .focusable(false)
            .environment(\.controlActiveState, .active)
            .scaleEffect(startHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: startHovered)
            .onHover { startHovered = $0 }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Recordings Panel

    var recordingsByMonth: [(key: String, recordings: [Recording])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy年MM月"
        let grouped = Dictionary(grouping: recorder.recordings) { fmt.string(from: $0.date) }
        return grouped.keys.sorted(by: >).map { key in
            (key: key, recordings: grouped[key]!.sorted { $0.date > $1.date })
        }
    }

    var recordingsPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Recordings")
                    .font(.headline)
                Text("(\(recorder.recordings.count))")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                Spacer()

                if !recorder.recordings.isEmpty {
                    Button("Delete All") { showDeleteConfirm = true }
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                        .focusable(false)
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
            .background(Color(nsColor: .windowBackgroundColor))

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
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                            ForEach(recordingsByMonth, id: \.key) { group in
                                Section {
                                    ForEach(group.recordings) { rec in
                                        RecordingRow(
                                            recording: rec,
                                            audioPlayer: audioPlayer,
                                            whisper: whisper,
                                            whisperModel: selectedWhisperModel,
                                            onDelete: { recorder.delete(rec) }
                                        )
                                        .id(rec.id)
                                        Divider()
                                            .padding(.leading, 20)
                                    }
                                } header: {
                                    Text(group.key)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.regularMaterial)
                                }
                            }
                        }
                    }
                    .background(ThinScrollBar())
                    .onChange(of: recorder.recordings.first?.id) { _ in
                        if let first = recorder.recordings.first {
                            proxy.scrollTo(first.id)
                        }
                    }
                    .onChange(of: audioPlayer.scrollTargetID) { id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }

            PlayerBar(audioPlayer: audioPlayer)
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

        let duration = totalSeconds
        recorder.startRecording {
            // endDate starts from when the mic actually opens, not when the button was pressed
            let endDate = Date().addingTimeInterval(TimeInterval(duration))
            self.timerTask = Task { @MainActor in
                repeat {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    self.timeRemaining = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
                } while self.timeRemaining > 0 && !Task.isCancelled
                guard !Task.isCancelled else { return }
                self.stopSession()
                self.sendCompletionNotification()
            }
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

    func importModelFile() {
        let panel = NSOpenPanel()
        panel.title = "选择 Whisper 模型文件"
        panel.message = "可同时选择多个 ggml-*.bin 文件，将自动识别并分别导入"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = []
        guard panel.runModal() == .OK else { return }

        let expectedNames = WhisperModel.allCases.map { $0.fileName }.joined(separator: "\n  ")

        // Phase 1: detect model for every file + check for duplicates (sync, instant)
        var plan: [(url: URL, model: WhisperModel)] = []
        var errors: [String] = []

        for url in panel.urls {
            let stem = url.deletingPathExtension().lastPathComponent
            let detected = WhisperModel.allCases.first(where: { url.lastPathComponent == $0.fileName })
                        ?? WhisperModel.allCases.first(where: {
                               let base = String($0.fileName.dropLast(4))
                               return stem.hasPrefix(base + " ") || stem.hasPrefix(base + "(")
                           })
            guard let model = detected else {
                errors.append("「\(url.lastPathComponent)」文件名不符合要求。\n支持的文件名：\n  \(expectedNames)")
                continue
            }
            if plan.contains(where: { $0.model == detected }) {
                errors.append("「\(url.lastPathComponent)」与已选文件重复（\(model.shortName)）。")
                continue
            }
            plan.append((url, model))
        }

        if !errors.isEmpty {
            importErrorMsg = errors.joined(separator: "\n\n")
            showImportError = true
            return
        }

        // Phase 2: run whisper-cli against each file to verify it loads (async)
        // Phase 3: copy all only if every file passes
        isValidatingImport = true
        Task {
            var validateErrors: [String] = []
            for item in plan {
                do {
                    try await whisper.validateModelWorks(item.model, at: item.url)
                } catch {
                    validateErrors.append("「\(item.url.lastPathComponent)」：\(error.localizedDescription)")
                }
            }

            isValidatingImport = false

            if !validateErrors.isEmpty {
                importErrorMsg = validateErrors.joined(separator: "\n\n")
                showImportError = true
                return
            }

            var lastImported: WhisperModel? = nil
            for item in plan {
                try? whisper.importModel(item.model, from: item.url)
                lastImported = item.model
            }
            if let last = lastImported { whisperModelRaw = last.rawValue }
        }
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
    @ObservedObject var audioPlayer: AudioPlayer
    let whisper: WhisperTranscriber
    let whisperModel: WhisperModel
    let onDelete: () -> Void

    var isPlaying: Bool { audioPlayer.currentRecording?.id == recording.id && audioPlayer.isPlaying }

    @State private var isHovered = false
    @State private var folderHovered = false
    @State private var transcribeHovered = false
    @State private var transcribeState: TranscribeState = .idle
    @State private var deleteHovered = false
    @State private var showDeleteConfirm = false
    @State private var showDownloadConfirm = false
    @State private var showTranscriptSheet = false
    @State private var transcriptText = ""
    @State private var transcribeError: String? = nil
    @State private var showTranscribeError = false

    enum TranscribeState {
        case idle, loading, failed
    }

    var formatBadgeColor: Color {
        switch recording.url.pathExtension.lowercased() {
        case "mp3": return .blue
        case "m4a": return .purple
        case "wav": return .green
        default: return .gray
        }
    }

    var isSelected: Bool { audioPlayer.currentRecording?.id == recording.id }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(recording.formattedDate)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                HStack(spacing: 4) {
                    Text(recording.formattedDuration)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                    Text(recording.url.pathExtension.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background((isSelected ? Color.white : formatBadgeColor).opacity(0.2))
                        .foregroundStyle(isSelected ? Color.white : formatBadgeColor)
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
            .focusable(false)
            .help("Show in Finder")
            .onHover { folderHovered = $0 }

            Button { transcribeTapped() } label: {
                Group {
                    switch transcribeState {
                    case .idle:
                        Image(systemName: "captions.bubble")
                            .foregroundStyle(transcribeHovered ? Color.accentColor : Color.secondary)
                    case .loading:
                        ProgressView().controlSize(.mini)
                    case .failed:
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(Color.red)
                    }
                }
                .scaleEffect(transcribeHovered && transcribeState == .idle ? 1.15 : 1.0)
                .animation(.spring(response: 0.15), value: transcribeHovered)
                .animation(.spring(response: 0.15), value: transcribeState)
                .frame(width: 16)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(whisper.isModelAvailable(whisperModel) ? "识别语音" : "请先导入模型")
            .onHover { transcribeHovered = $0 }
            .disabled(transcribeState == .loading)
            .alert("识别失败", isPresented: $showTranscribeError) {
                Button("好") { transcribeState = .idle }
            } message: {
                Text(transcribeError ?? "未知错误")
            }
            .alert("模型未导入", isPresented: $showDownloadConfirm) {
                Button("好") {}
            } message: {
                Text("请先在 Recordings 栏头部点击 📁 导入 \(whisperModel.shortName) 模型。")
            }
            .sheet(isPresented: $showTranscriptSheet) {
                TranscriptSheet(text: transcriptText, isPresented: $showTranscriptSheet)
            }

            Button { showDeleteConfirm = true } label: {
                Image(systemName: "trash")
                    .foregroundStyle(deleteHovered ? Color.red : Color.secondary)
                    .scaleEffect(deleteHovered ? 1.15 : 1.0)
                    .animation(.spring(response: 0.15), value: deleteHovered)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { deleteHovered = $0 }
            .confirmationDialog("Delete \"\(recording.formattedDate)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            isSelected
                ? Color.accentColor.opacity(0.75)
                : (isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onHover { isHovered = $0 }
        .simultaneousGesture(TapGesture(count: 2).onEnded { togglePlay() })
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
    }

    func transcribeTapped() {
        if whisper.isModelAvailable(whisperModel) {
            doTranscribe()
        } else {
            showDownloadConfirm = true
        }
    }

    func doTranscribe() {
        transcribeState = .loading
        Task {
            do {
                let text = try await whisper.transcribe(url: recording.url, model: whisperModel)
                await MainActor.run {
                    transcriptText = text
                    transcribeState = .idle
                    showTranscriptSheet = true
                }
            } catch {
                await MainActor.run {
                    transcribeError = error.localizedDescription
                    transcribeState = .failed
                    showTranscribeError = true
                }
            }
        }
    }

    func togglePlay() {
        audioPlayer.toggle(recording)
    }
}

// MARK: - Player Bar

struct PlayerBar: View {
    @ObservedObject var audioPlayer: AudioPlayer
    @State private var showVolume = false

    private var progress: Double {
        audioPlayer.duration > 0 ? audioPlayer.currentTime / audioPlayer.duration : 0
    }

    private var volumeIcon: String {
        switch audioPlayer.volume {
        case 0: return "speaker.slash.fill"
        case ..<0.4: return "speaker.fill"
        case ..<0.75: return "speaker.wave.1.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    // Play / pause
                    Button {
                        if audioPlayer.isPlaying {
                            audioPlayer.pause()
                        } else {
                            audioPlayer.resume()
                            audioPlayer.scrollTargetID = audioPlayer.currentRecording?.id
                        }
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(audioPlayer.currentRecording == nil
                                ? Color.secondary.opacity(0.4)
                                : (audioPlayer.isPlaying ? Color.orange : Color.accentColor))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(audioPlayer.currentRecording == nil)

                    // Slider
                    Slider(
                        value: Binding(
                            get: { progress },
                            set: { audioPlayer.seek(to: $0 * audioPlayer.duration) }
                        )
                    )
                    .disabled(audioPlayer.currentRecording == nil)
                    .focusable(false)

                    // Volume
                    Button { showVolume.toggle() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: volumeIcon)
                                .font(.system(size: 13))
                            Text("\(Int(audioPlayer.volume * 100))%")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .popover(isPresented: $showVolume, arrowEdge: .top) {
                        VStack(spacing: 8) {
                            Text("音量")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { Double(audioPlayer.volume) },
                                set: { audioPlayer.volume = Float($0) }
                            ), in: 0...1)
                            .frame(width: 120)
                            .focusable(false)
                            Text("\(Int(audioPlayer.volume * 100))%")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                    }
                }

                // Name + time below slider
                HStack {
                    Text(audioPlayer.currentRecording.map { $0.formattedDate } ?? "–")
                        .font(.caption)
                        .foregroundStyle(audioPlayer.currentRecording == nil ? .tertiary : .secondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(formatTime(audioPlayer.currentTime)) / \(formatTime(audioPlayer.duration))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - Model Info Popover

struct ModelInfoPopover: View {
    let model: WhisperModel
    @Binding var isPresented: Bool
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cube.box")
                    .foregroundStyle(.secondary)
                Text("Whisper \(model.shortName) 模型")
                    .font(.headline)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Group {
                LabeledRow(label: "文件名", value: model.fileName)
                LabeledRow(label: "大小", value: model.displayName.components(separatedBy: "(").last.map { "(" + $0 } ?? "")
                LabeledRow(label: "格式", value: "GGML 二进制格式（whisper.cpp 专用）")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("下载地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.downloadURL.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.downloadURL.absoluteString, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制链接", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .tint(copied ? .green : .accentColor)
                .controlSize(.small)

                Spacer()

                Button("在浏览器打开") {
                    NSWorkspace.shared.open(model.downloadURL)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Transcript Sheet

struct SelectableTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.string = text
    }
}

struct TranscriptSheet: View {
    let text: String
    @Binding var isPresented: Bool
    @State private var copied = false
    @State private var closeHovered = false
    @State private var copyHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("识别结果")
                    .font(.headline)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(closeHovered ? Color.primary : Color.secondary)
                        .scaleEffect(closeHovered ? 1.15 : 1.0)
                        .animation(.spring(response: 0.15), value: closeHovered)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .onHover { closeHovered = $0 }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            SelectableTextView(text: text)
                .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .tint(copied ? .green : .accentColor)
                .focusable(false)
                .scaleEffect(copyHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.15), value: copyHovered)
                .onHover { copyHovered = $0 }

            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420, height: 320)
    }
}

// MARK: - Thin scroll bar helper

struct ThinScrollBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { applyOverlayScroller(view) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private func applyOverlayScroller(_ view: NSView) {
        var v: NSView? = view
        while let current = v {
            if let scrollView = current as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                return
            }
            v = current.superview
        }
    }
}

// MARK: - Window title hider

struct WindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.titleVisibility = .hidden
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.titleVisibility = .hidden
        }
    }
}
