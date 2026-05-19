# SushiSpeak 🍣

A native macOS app for English speaking practice. Set a countdown timer, hit Start — it records your voice and saves the audio when time's up.

## Features

- **Countdown timer** — MM:SS format, remembers your last setting across launches
- **Auto record** — starts recording when you hit Start, stops and saves when time is up
- **Live waveform** — animated bars driven by real microphone audio level (flat when silent)
- **Recording list** — every session saved with date and duration
  - ▶ Play back inline
  - 📁 Reveal in Finder
  - 📄 Copy file to clipboard
  - 🗑 Delete with confirmation dialog
  - Delete All with confirmation
- **System notification** — banner + sound when session completes
- **Audio format** — MP3 (falls back to M4A if encoder unavailable)
- **Gain boost** — 2.5× input amplification so normal speaking volume comes out clearly

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```bash
cd ~/code/SushiSpeak
./build.sh          # compiles, packages, kills old instance, opens new build
```

Output: `.build/SushiSpeak.app`

Install permanently:
```bash
cp -r .build/SushiSpeak.app ~/Applications/
```

## First Launch

1. Grant **Microphone** permission when prompted
2. Grant **Notifications** permission when prompted (required for end-of-session alert)
   - If you accidentally denied: System Settings → Notifications → SushiSpeak → Allow

## Recordings Location

`~/Documents/SushiSpeak/rec_<timestamp>.mp3`
