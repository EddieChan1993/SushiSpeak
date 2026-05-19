#!/bin/bash
set -e

APP_NAME="SushiSpeak"
BUILD_TYPE="${1:-release}"
BUILD_DIR=".build"

echo "🍣 Building $APP_NAME ($BUILD_TYPE)..."

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

# Create bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/$BUILD_TYPE/$APP_NAME" "$MACOS_DIR/$APP_NAME"

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
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
PLIST

# Write entitlements (microphone access, no sandbox for ad-hoc)
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

# Ad-hoc code sign with entitlements
codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$BUILD_DIR/$APP_NAME.entitlements" \
    "$APP_BUNDLE"

echo ""
echo "✅ Build complete: $APP_BUNDLE"
open "$APP_BUNDLE"
