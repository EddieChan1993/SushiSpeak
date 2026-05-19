# SushiSpeak — Claude Notes

macOS SwiftUI app for English speaking practice. Swift Package Manager, no Xcode project.

## Build command (always return this after any change)

```bash
cd ~/code/SushiSpeak && ./build.sh
```

`build.sh` kills running instance → `swift build -c release` → assembles `.app` bundle → code-signs → `open`.

## Project structure

```
Sources/SushiSpeak/
  SushiSpeakApp.swift   — @main, UNUserNotificationCenterDelegate setup
  ContentView.swift     — UI: timer panel, waveform, recordings list
  AudioRecorder.swift   — AVAudioEngine recording + gain boost + RMS metering
  Recording.swift       — data model (id, url, date, duration)
```

## Key decisions & rationale

### Audio recording: AVAudioEngine (not AVAudioRecorder)
`AVAudioRecorder` has no gain control. We use `AVAudioEngine` + `AVAudioMixerNode` with `outputVolume = 2.5` (~8 dB boost) so normal speaking volume records clearly.

### Audio format: MP3 with M4A fallback
`kAudioFormatMPEGLayer3` + `.mp3` extension. macOS may have the Fraunhofer encoder; if `AVAudioFile(forWriting:)` fails we fall back to M4A (AAC). WAV was tried but 豆包 doesn't accept it.

**Critical**: extension must match format. `.mp3` + LinearPCM = silent failure. `.wav` + LinearPCM = works. `.mp3` + kAudioFormatMPEGLayer3 = works if encoder available.

### Timer settings persistence: @AppStorage
`selectedMinutes` and `selectedSeconds` use `@AppStorage` (UserDefaults). `timeRemaining` syncs via `.onAppear { timeRemaining = totalSeconds }`.

### Waveform: real RMS metering with noise gate
Tap callback computes RMS per 4096-sample buffer. Noise gate: RMS < 0.012 → level = 0 (flat bars). Exponential smoothing (`old × 0.55 + new × 0.45`) prevents choppy animation at 20 Hz update rate. `TimelineView(.animation)` drives 60 fps bar rendering.

### Notification: requires delegate for foreground display
`UNUserNotificationCenter` only shows notifications in foreground if delegate implements `willPresent` returning `[.banner, .sound]`. Delegate is set in `SushiSpeakApp.init()` before any auth request. Info.plist has `NSUserNotificationAlertStyle = alert`.

### Focus lock during recording
Duration pickers hidden with `.opacity(0)` + `.disabled(isRunning)` + `.allowsHitTesting(!isRunning)`. Opacity-only was insufficient — space bar still cycled keyboard focus to hidden pickers.

### Height stability on Start
Both waveform and duration picker live in a `ZStack` with fixed `height: 48`, toggled by `.opacity`. Conditional `if/else` caused layout jump.

## Known issues / watch out

- If user denied notifications on first launch, they must re-enable in System Settings → Notifications → SushiSpeak.
- MP3 encoding availability depends on macOS version; M4A fallback is silent (no UI indication of which format was used).
- `AVAudioEngine.inputNode.outputFormat` is queried after mic permission granted; calling it before causes a crash.
- `booster.removeTap(onBus: 0)` must be called before `engine.stop()`, otherwise occasional EXC_BAD_ACCESS on rapid start/stop.
