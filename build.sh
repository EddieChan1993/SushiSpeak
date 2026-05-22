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

# Keep the .app directory itself so macOS TCC retains microphone permission
# across rebuilds. Only wipe Contents/ to remove stale files.
rm -rf "$CONTENTS"
mkdir -p "$APP_BUNDLE" "$MACOS_DIR" "$RESOURCES_DIR"

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

# Production: bundle ffmpeg and whisper-cli so the app works without Homebrew
if [ "$DEV_MODE" = false ]; then
    # --- ffmpeg ---
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

    # --- whisper-cli + dylibs + backend plugins ---
    WHISPER_CLI_SRC=""
    for p in /opt/homebrew/bin/whisper-cli /usr/local/bin/whisper-cli; do
        if [ -f "$p" ]; then WHISPER_CLI_SRC="$p"; break; fi
    done

    if [ -n "$WHISPER_CLI_SRC" ]; then
        cp "$WHISPER_CLI_SRC" "$MACOS_DIR/whisper-cli"

        # Copy libwhisper
        WHISPER_VER=$(ls /opt/homebrew/Cellar/whisper-cpp/ 2>/dev/null | head -1)
        WHISPER_LIB="/opt/homebrew/Cellar/whisper-cpp/$WHISPER_VER/lib/libwhisper.1.dylib"
        if [ -f "$WHISPER_LIB" ]; then
            cp "$WHISPER_LIB" "$MACOS_DIR/libwhisper.1.dylib"
        fi

        # Copy ggml libs
        GGML_LIB_DIR="/opt/homebrew/opt/ggml/lib"
        for lib in libggml.0.dylib libggml-base.0.dylib; do
            [ -f "$GGML_LIB_DIR/$lib" ] && cp "$GGML_LIB_DIR/$lib" "$MACOS_DIR/$lib"
        done

        # Copy ggml backend plugins (.so) — metal, blas, cpu variants
        GGML_LIBEXEC="/opt/homebrew/opt/ggml/libexec"
        if [ -d "$GGML_LIBEXEC" ]; then
            cp "$GGML_LIBEXEC"/libggml-*.so "$MACOS_DIR/" 2>/dev/null || true
        fi

        # Fix rpath on whisper-cli binary
        install_name_tool -add_rpath "@executable_path" "$MACOS_DIR/whisper-cli" 2>/dev/null || true
        install_name_tool \
            -change "/opt/homebrew/opt/ggml/lib/libggml.0.dylib" "@rpath/libggml.0.dylib" \
            -change "/opt/homebrew/opt/ggml/lib/libggml-base.0.dylib" "@rpath/libggml-base.0.dylib" \
            "$MACOS_DIR/whisper-cli" 2>/dev/null || true

        # Fix rpath on libwhisper
        if [ -f "$MACOS_DIR/libwhisper.1.dylib" ]; then
            install_name_tool -id "@rpath/libwhisper.1.dylib" "$MACOS_DIR/libwhisper.1.dylib" 2>/dev/null || true
            install_name_tool -add_rpath "@loader_path" "$MACOS_DIR/libwhisper.1.dylib" 2>/dev/null || true
            install_name_tool \
                -change "/opt/homebrew/opt/ggml/lib/libggml.0.dylib" "@loader_path/libggml.0.dylib" \
                -change "/opt/homebrew/opt/ggml/lib/libggml-base.0.dylib" "@loader_path/libggml-base.0.dylib" \
                "$MACOS_DIR/libwhisper.1.dylib" 2>/dev/null || true
        fi

        # Fix rpath on libggml
        if [ -f "$MACOS_DIR/libggml.0.dylib" ]; then
            install_name_tool -id "@rpath/libggml.0.dylib" "$MACOS_DIR/libggml.0.dylib" 2>/dev/null || true
            install_name_tool -add_rpath "@loader_path" "$MACOS_DIR/libggml.0.dylib" 2>/dev/null || true
            install_name_tool \
                -change "@rpath/libggml-base.0.dylib" "@loader_path/libggml-base.0.dylib" \
                "$MACOS_DIR/libggml.0.dylib" 2>/dev/null || true
        fi

        # Fix id on libggml-base
        if [ -f "$MACOS_DIR/libggml-base.0.dylib" ]; then
            install_name_tool -id "@rpath/libggml-base.0.dylib" "$MACOS_DIR/libggml-base.0.dylib" 2>/dev/null || true
        fi

        WHISPER_SIZE=$(du -sh "$MACOS_DIR"/libggml*.dylib "$MACOS_DIR/libwhisper.1.dylib" "$MACOS_DIR/whisper-cli" "$MACOS_DIR"/libggml*.so 2>/dev/null | awk '{sum += $1} END {print sum}')
        echo "  Bundled: whisper-cli + dylibs + backends"
    else
        echo "  ⚠️  whisper-cli not found — install with: brew install whisper-cpp"
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
