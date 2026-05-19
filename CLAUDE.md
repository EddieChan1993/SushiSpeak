# SushiSpeak — Claude Notes

macOS SwiftUI app for English speaking practice. Swift Package Manager, no Xcode project.

## Build command (always return this after any change)

```bash
cd ~/code/SushiSpeak && ./build.sh
```

`build.sh` kills running instance → `swift build -c release` → assembles `.app` bundle → code-signs → `open`.

Use `-d` flag for dev mode: debug build, skips bundling external tools.

## Project structure

```
Sources/SushiSpeak/
  SushiSpeakApp.swift   — @main entry point
  ContentView.swift     — UI: timer panel, format picker, waveform, recordings list
  AudioRecorder.swift   — AVAudioEngine recording + gain boost + RMS metering + transcription
  Recording.swift       — data model (id, url, date, duration)
```

## Key decisions & rationale

### Audio recording: AVAudioEngine (not AVAudioRecorder)
`AVAudioRecorder` has no gain control. We use `AVAudioEngine` + `AVAudioMixerNode` with `outputVolume = 2.5` (~8 dB boost) so normal speaking volume records clearly.

### Audio format pipeline
Always record as M4A (AAC) — most reliable on macOS. After stopping, convert to user's selected format via ffmpeg:
- **MP3**: `ffmpeg -y -i rec.m4a -q:a 2 rec.mp3`
- **WAV**: `ffmpeg -y -i rec.m4a rec.wav`
- **M4A**: no conversion needed, keep as-is

User selects format via picker in the timer panel; stored in `@AppStorage("audioFormat")`.

**Why not native MP3?** macOS AVFoundation has no MP3 encoder. `kAudioFormatMPEGLayer3` sometimes works but is unreliable. ffmpeg is the only solid path.

**Critical**: extension must match format. `.mp3` + LinearPCM = silent failure.

**豆包 compatibility**: WAV was rejected, AAC was rejected. MP3 works.

### ffmpeg: bundled in production, system in dev
Production build (`./build.sh`) copies Homebrew ffmpeg into `Contents/MacOS/ffmpeg`.
Dev build (`./build.sh -d`) uses system ffmpeg at `/opt/homebrew/bin/ffmpeg` or `/usr/local/bin/ffmpeg`.

`AudioRecorder.ffmpegPath` checks bundle-relative path first:
```swift
Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("ffmpeg").path
```
then falls back to Homebrew paths.

### Transcription (copy/transcribe button)
Clicking the `waveform.and.mic` button in each recording row:
1. Calls `SFSpeechRecognizer` with `zh-CN` locale (falls back to `en-US`)
2. Shows `ProgressView` while transcribing
3. On success: copies text to clipboard, shows green checkmark for 2s
4. On failure: shows red X for 2s

`SFSpeechRecognizer` handles Chinese, English, and mixed (depending on locale/model). No separate permission UI — iOS-style prompt appears on first use.

### Format badge in recording list
Each `RecordingRow` reads `recording.url.pathExtension` and shows a small colored pill:
- MP3 → blue
- M4A → purple
- WAV → green

### Timer settings persistence: @AppStorage
`selectedMinutes`, `selectedSeconds`, and `audioFormatRaw` use `@AppStorage` (UserDefaults).

### Waveform: real RMS metering with noise gate
Tap callback computes RMS per 4096-sample buffer. Noise gate: RMS < 0.012 → level = 0 (flat bars). Exponential smoothing (`old × 0.55 + new × 0.45`) prevents choppy animation. `TimelineView(.animation)` drives 60 fps bar rendering.

### Completion alert: NSSound + requestUserAttention
`UNUserNotificationCenter` silently fails for non-sandboxed SPM apps (no permission prompt).
`NSUserNotificationCenter` is deprecated and broken on macOS 12+.
Final solution: `NSSound(named: "Glass")?.play()` + `NSApp.requestUserAttention(.criticalRequest)`.

### Focus lock during recording
Duration pickers hidden with `.opacity(0)` + `.disabled(isRunning)` + `.allowsHitTesting(!isRunning)`. Opacity-only was insufficient — space bar still cycled keyboard focus to hidden pickers.

### Height stability on Start
Both waveform and duration picker live in a `ZStack` with fixed `height: 48`, toggled by `.opacity`. Conditional `if/else` caused layout jump.

## Known issues / watch out

- `AVAudioEngine.inputNode.outputFormat` must only be queried after mic permission is granted; calling it before causes a crash.
- `booster.removeTap(onBus: 0)` must be called before `engine.stop()`, otherwise occasional EXC_BAD_ACCESS on rapid start/stop.
- Speech recognition accuracy for mixed Chinese/English depends on the system locale and model availability.
- If ffmpeg is not found (dev mode, system not installed), M4A files are kept as-is without conversion.
- MP3 encoding availability on the target machine doesn't matter — we always record M4A and convert via bundled ffmpeg.
