#!/bin/bash
set -e

APP_NAME="SushiSpeak"
BUILD_DIR=".build"
DEV_MODE=false

# -d flag = development mode (debug build, use system tools, no bundling)
if [[ "$1" == "-d" ]]; then
    DEV_MODE=true
    BUILD_TYPE="debug"
else
    BUILD_TYPE="release"
fi

echo "🍣 Building $APP_NAME ($BUILD_TYPE, dev=$DEV_MODE)..."

# Kill any running instance
if pgrep -x "$APP_NAME" > /dev/null; then
    echo "Stopping running $APP_NAME..."
    pkill -x "$APP_NAME"
    sleep 0.5
fi

# Compile
swift build -c "$BUILD_TYPE"

# Bundle paths
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$BUILD_TYPE/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Copy app icon
if [ -f "Assets/AppIcon.icns" ]; then
    cp "Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    echo "  Bundled: AppIcon.icns"
fi

# Write Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SushiSpeak</string>
    <key>CFBundleIdentifier</key>
    <string>com.sushispeak.app</string>
    <key>CFBundleName</key>
    <string>SushiSpeak</string>
    <key>CFBundleDisplayName</key>
    <string>SushiSpeak</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>SushiSpeak needs microphone access to record your speaking practice sessions.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>SushiSpeak uses speech recognition to transcribe your recordings.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

# Write entitlements
cat > "$BUILD_DIR/$APP_NAME.entitlements" << 'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
ENT

# Production: bundle ffmpeg so the app works on machines without Homebrew
if [ "$DEV_MODE" = false ]; then
    FFMPEG_SRC=""
    for p in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
        if [ -f "$p" ]; then FFMPEG_SRC="$p"; break; fi
    done
    if [ -n "$FFMPEG_SRC" ]; then
        cp "$FFMPEG_SRC" "$MACOS_DIR/ffmpeg"
        echo "  Bundled: ffmpeg ($(du -sh "$MACOS_DIR/ffmpeg" | cut -f1))"
    else
        echo "  ⚠️  ffmpeg not found — MP3 conversion unavailable"
    fi
fi

codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$BUILD_DIR/$APP_NAME.entitlements" \
    "$APP_BUNDLE"

echo ""
echo "✅ Build complete: $APP_BUNDLE"
open "$APP_BUNDLE"
