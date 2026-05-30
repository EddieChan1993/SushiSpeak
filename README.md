# SushiSpeak

A native macOS app for English speaking practice. Set a countdown timer, hit Start — it records your voice, shows a live waveform, and saves the audio when time's up.

![SushiSpeak App Screenshot](screenshots/app.png)

## Features

- **Countdown timer** — MM:SS display, stepper controls for minutes and seconds, persists across launches
- **Auto record** — starts recording on Start, stops and saves on timeout or manual Stop
- **Live waveform** — animated bars driven by real microphone RMS level (flat when silent)
- **Audio format** — choose MP3 / M4A / WAV per session; format badge shown on each recording
- **Gain boost** — 2.5× input amplification so normal speaking volume comes out clearly
- **Recording list**
  - ▶ Play back inline
  - 📁 Reveal in Finder
  - 🎙 Transcribe with Whisper → result shown in popup, one-click copy
  - 🗑 Delete with confirmation; Delete All
- **Whisper transcription** — local on-device AI (whisper-cpp), supports Chinese / English / mixed
  - Models: Tiny / Base / Small (default) / Medium / Large V3
  - Download models in-app; progress shown in header
- **System alert** — sound + Dock bounce when session ends (no notification permissions needed)

## Requirements

- macOS 13 or later
- Xcode Command Line Tools: `xcode-select --install`
- ffmpeg (Homebrew): `brew install ffmpeg` *(for dev mode only — bundled in production build)*
- whisper-cpp (Homebrew): `brew install whisper-cpp` *(for dev mode only — bundled in production build)*

## Build & Run

```bash
cd ~/code/SushiSpeak
./build.sh          # release build: bundles ffmpeg + whisper-cli, opens app
./build.sh -d       # dev build: uses system Homebrew tools, faster iteration
```

Output: `.build/SushiSpeak.app`

Install permanently:
```bash
cp -r .build/SushiSpeak.app ~/Applications/
```

## Whisper Models

Click 🌐 in the header to open the model download page, download any `ggml-*.bin` file, then click 📁 to select it. The loaded model is shown as a chip — click × to remove.

Download page: https://huggingface.co/ggerganov/whisper.cpp/tree/main

| Model | File | Size |
|-------|------|------|
| Tiny | `ggml-tiny.bin` | ~75 MB |
| Base | `ggml-base.bin` | ~142 MB |
| Small | `ggml-small.bin` | ~466 MB |
| Medium | `ggml-medium.bin` | ~1.5 GB |
| Large V3 | `ggml-large-v3.bin` | ~3.1 GB |
| Large V3 Turbo | `ggml-large-v3-turbo.bin` | ~1.6 GB |

Models are stored in `~/Library/Application Support/SushiSpeak/models/`.

## Recordings Location

`~/Documents/SushiSpeak/rec_<timestamp>.<format>`

---

## 版权声明

Copyright © 2026 EddieChan1993. All rights reserved.

本软件及其源代码受版权法保护。

- **禁止未经授权的商业使用**：未获得作者书面授权，不得将本软件或其任何衍生版本用于任何商业目的，包括但不限于销售、出租、捆绑销售或以盈利为目的的分发。
- **个人学习使用**：仅允许在获得授权的设备上用于个人非商业用途。
- **禁止二次分发**：未经授权不得以任何形式转发、再分发本软件的安装包或源代码。

如需商业授权或合作，请联系：**wx DC_Wen** 或邮箱 **dc_wen666666@163.com**
