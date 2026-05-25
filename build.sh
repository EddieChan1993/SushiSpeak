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

# ─── Helper: copy a dylib and rewrite its install name to @rpath ───────────
copy_dylib() {
    local src="$1"
    local dst="$MACOS_DIR/$(basename "$src")"
    [ -f "$src" ] || return 0
    cp "$src" "$dst"
    local id
    id=$(otool -D "$dst" 2>/dev/null | tail -1)
    local name
    name=$(basename "$id")
    install_name_tool -id "@rpath/$name" "$dst" 2>/dev/null || true
}

# ─── Helper: rewrite all non-system dylib references to @rpath ─────────────
fix_refs() {
    local bin="$1"
    while IFS= read -r line; do
        # lines like: /opt/homebrew/... (compatibility ...)
        local path
        path=$(echo "$line" | awk '{print $1}')
        [[ "$path" == /* ]] || continue
        [[ "$path" == /usr/lib/* || "$path" == /System/* ]] && continue
        local name
        name=$(basename "$path")
        install_name_tool -change "$path" "@rpath/$name" "$bin" 2>/dev/null || true
    done < <(otool -L "$bin" 2>/dev/null | tail -n +2)
}

# ─── Production bundle ──────────────────────────────────────────────────────
if [ "$DEV_MODE" = false ]; then

    # ffmpeg (self-contained static build — no extra dylibs needed)
    FFMPEG_SRC=""
    for p in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
        [ -f "$p" ] && { FFMPEG_SRC="$p"; break; }
    done
    if [ -n "$FFMPEG_SRC" ]; then
        cp "$FFMPEG_SRC" "$MACOS_DIR/ffmpeg"
        strip -x "$MACOS_DIR/ffmpeg" 2>/dev/null || true
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
        strip -x "$MACOS_DIR/whisper-cli" 2>/dev/null || true

        # Discover and copy all non-system dylib deps of whisper-cli
        while IFS= read -r line; do
            local_path=$(echo "$line" | awk '{print $1}')
            [[ "$local_path" == /* ]] || continue
            [[ "$local_path" == /usr/lib/* || "$local_path" == /System/* ]] && continue
            copy_dylib "$local_path"
        done < <(otool -L "$WHISPER_CLI_SRC" 2>/dev/null | tail -n +2)

        # Also pull libwhisper (may not be a direct dep of whisper-cli on some versions)
        WHISPER_VER=$(ls /opt/homebrew/Cellar/whisper-cpp/ 2>/dev/null | sort -V | tail -1)
        WHISPER_LIB="/opt/homebrew/Cellar/whisper-cpp/$WHISPER_VER/lib/libwhisper.1.dylib"
        copy_dylib "$WHISPER_LIB"

        # ggml backend plugins (.so) — keep all CPU variants for cross-machine compat
        GGML_LIBEXEC="/opt/homebrew/opt/ggml/libexec"
        if [ -d "$GGML_LIBEXEC" ]; then
            for so in "$GGML_LIBEXEC"/libggml-*.so; do
                [ -f "$so" ] && cp "$so" "$MACOS_DIR/"
            done
        fi

        # Add @executable_path rpath so bundled dylibs are found
        install_name_tool -add_rpath "@executable_path" "$MACOS_DIR/whisper-cli" 2>/dev/null || true

        # Rewrite all hardcoded Homebrew paths → @rpath in every bundled binary
        for bin in "$MACOS_DIR/whisper-cli" "$MACOS_DIR"/*.dylib "$MACOS_DIR"/*.so; do
            [ -f "$bin" ] && fix_refs "$bin"
        done

        echo "  Bundled: whisper-cli + dylibs + backends"
    else
        echo "  ⚠️  whisper-cli not found — brew install whisper-cpp"
    fi

    # Clear quarantine so the app runs on another Mac without Gatekeeper prompt
    xattr -cr "$APP_BUNDLE" 2>/dev/null || true

fi

# Sign each binary individually, then the whole bundle
find "$MACOS_DIR" -type f \( -name "*.dylib" -o -name "*.so" \) | while read -r lib; do
    codesign --force --sign - "$lib" 2>/dev/null || true
done
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
[ -f "$MACOS_DIR/whisper-cli" ] && codesign --force --sign - "$MACOS_DIR/whisper-cli" 2>/dev/null || true
[ -f "$MACOS_DIR/ffmpeg" ]      && codesign --force --sign - "$MACOS_DIR/ffmpeg"      2>/dev/null || true
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

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
