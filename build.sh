#!/bin/bash
set -e

APP_NAME="SushiSpeak"
BUILD_DIR=".build"
DEV_MODE=false
DIST_MODE=false

for arg in "$@"; do
    case $arg in
        -h|--help)
            echo "Usage: ./build.sh [options]"
            echo ""
            echo "Options:"
            echo "  (none)   Release build, bundle all tools, launch app"
            echo "  -d       Dev mode: debug build, use system Homebrew tools, skip bundling"
            echo "  -dist    Release build + create SushiSpeak.zip for distribution"
            echo "  -h       Show this help"
            echo ""
            echo "Examples:"
            echo "  ./build.sh           # 日常开发"
            echo "  ./build.sh -dist     # 打包发给别人"
            echo "  ./build.sh -d        # 快速调试"
            exit 0
            ;;
        -d) DEV_MODE=true ;;
        -dist) DIST_MODE=true ;;
    esac
done

BUILD_TYPE=$( [ "$DEV_MODE" = true ] && echo "debug" || echo "release" )
echo "🍣 Building $APP_NAME ($BUILD_TYPE, dev=$DEV_MODE, dist=$DIST_MODE)..."

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
ENTITLEMENTS="$BUILD_DIR/$APP_NAME.entitlements"

# Keep .app dir to preserve TCC microphone permission; wipe only Contents/
rm -rf "$CONTENTS"
mkdir -p "$APP_BUNDLE" "$MACOS_DIR" "$RESOURCES_DIR"

# Copy + strip main binary
cp "$BUILD_DIR/$BUILD_TYPE/$APP_NAME" "$MACOS_DIR/$APP_NAME"
strip -x "$MACOS_DIR/$APP_NAME"

# App icon
if [ -f "Assets/AppIcon.icns" ]; then
    cp "Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Info.plist
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

# Entitlements
cat > "$ENTITLEMENTS" << 'ENT'
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

# ─── Production bundle ──────────────────────────────────────────────────────
if [ "$DEV_MODE" = false ]; then

    # ffmpeg
    FFMPEG_SRC=""
    for p in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
        [ -f "$p" ] && { FFMPEG_SRC="$p"; break; }
    done
    if [ -n "$FFMPEG_SRC" ]; then
        cp "$FFMPEG_SRC" "$MACOS_DIR/ffmpeg"
        echo "  Bundled: ffmpeg ($(du -sh "$MACOS_DIR/ffmpeg" | cut -f1))"
    else
        echo "  ⚠️  ffmpeg not found"
    fi

    # whisper-cli
    WHISPER_CLI_SRC=""
    for p in /opt/homebrew/bin/whisper-cli /usr/local/bin/whisper-cli; do
        [ -f "$p" ] && { WHISPER_CLI_SRC="$p"; break; }
    done

    if [ -n "$WHISPER_CLI_SRC" ]; then
        cp "$WHISPER_CLI_SRC" "$MACOS_DIR/whisper-cli"

        # libwhisper
        WHISPER_VER=$(ls /opt/homebrew/Cellar/whisper-cpp/ 2>/dev/null | head -1)
        WHISPER_LIB="/opt/homebrew/Cellar/whisper-cpp/$WHISPER_VER/lib/libwhisper.1.dylib"
        [ -f "$WHISPER_LIB" ] && cp "$WHISPER_LIB" "$MACOS_DIR/libwhisper.1.dylib"

        # ggml core dylibs
        GGML_LIB_DIR="/opt/homebrew/opt/ggml/lib"
        for lib in libggml.0.dylib libggml-base.0.dylib; do
            [ -f "$GGML_LIB_DIR/$lib" ] && cp "$GGML_LIB_DIR/$lib" "$MACOS_DIR/$lib"
        done

        # ggml backend plugins (.so) — all CPU variants for cross-machine compat
        GGML_LIBEXEC="/opt/homebrew/opt/ggml/libexec"
        [ -d "$GGML_LIBEXEC" ] && cp "$GGML_LIBEXEC"/libggml-*.so "$MACOS_DIR/" 2>/dev/null || true

        # Fix rpath on whisper-cli
        install_name_tool -add_rpath "@executable_path" "$MACOS_DIR/whisper-cli" 2>/dev/null || true
        install_name_tool \
            -change "/opt/homebrew/opt/ggml/lib/libggml.0.dylib"      "@rpath/libggml.0.dylib" \
            -change "/opt/homebrew/opt/ggml/lib/libggml-base.0.dylib" "@rpath/libggml-base.0.dylib" \
            "$MACOS_DIR/whisper-cli" 2>/dev/null || true

        # Fix rpath on libwhisper
        if [ -f "$MACOS_DIR/libwhisper.1.dylib" ]; then
            install_name_tool -id "@rpath/libwhisper.1.dylib" "$MACOS_DIR/libwhisper.1.dylib" 2>/dev/null || true
            install_name_tool -add_rpath "@loader_path" "$MACOS_DIR/libwhisper.1.dylib" 2>/dev/null || true
            install_name_tool \
                -change "/opt/homebrew/opt/ggml/lib/libggml.0.dylib"      "@loader_path/libggml.0.dylib" \
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

        echo "  Bundled: whisper-cli + dylibs + backends"
    else
        echo "  ⚠️  whisper-cli not found — brew install whisper-cpp"
    fi

    # Clear quarantine so the app runs on another Mac without Gatekeeper prompt
    xattr -cr "$APP_BUNDLE" 2>/dev/null || true

fi

codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo ""
echo "✅ Build complete: $APP_BUNDLE"

# -dist: create a zip for sharing
if [ "$DIST_MODE" = true ]; then
    ZIP_PATH="$APP_NAME.zip"
    rm -f "$ZIP_PATH"
    cd "$BUILD_DIR"
    zip -qr "../$ZIP_PATH" "$APP_NAME.app"
    cd - > /dev/null
    echo "📦 Distribution zip: $(pwd)/$ZIP_PATH ($(du -sh "$ZIP_PATH" | cut -f1))"
    echo "   → 目标机器首次打开：右键 → 打开，或运行："
    echo "     xattr -dr com.apple.quarantine $APP_NAME.app"
    open -R "$ZIP_PATH"
else
    open "$APP_BUNDLE"
fi
