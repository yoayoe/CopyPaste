#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Build CopyPaste .dmg package for macOS
# Usage: ./scripts/build-dmg.sh
#
# Prerequisites:
#   - macOS with Xcode CLI tools
#   - Flutter SDK
#   - Optional: create-dmg (brew install create-dmg)
# ─────────────────────────────────────────────

APP_NAME="copypaste"
APP_DISPLAY_NAME="CopyPaste"
APP_VERSION="0.2.0"
APP_BUNDLE_NAME="copypaste.app"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
MACOS_BUILD_DIR="$BUILD_DIR/macos/Build/Products/Release"
DMG_DIR="$BUILD_DIR/dmg"
DMG_FILE="$BUILD_DIR/${APP_DISPLAY_NAME}_${APP_VERSION}.dmg"

# ─── Helper function ───
build_dmg_simple() {
    echo "  Using hdiutil..."
    cp -R "$MACOS_BUILD_DIR/$APP_BUNDLE_NAME" "$DMG_DIR/"
    ln -s /Applications "$DMG_DIR/Applications"
    hdiutil create \
        -volname "$APP_DISPLAY_NAME" \
        -srcfolder "$DMG_DIR" \
        -ov \
        -format UDZO \
        "$DMG_FILE"
}

echo "=== Building CopyPaste .dmg package ==="
echo "Version: $APP_VERSION"
echo "Project: $PROJECT_DIR"

# Check we're on macOS
if [ "$(uname)" != "Darwin" ]; then
    echo "ERROR: This script must be run on macOS"
    exit 1
fi

# Step 1: Build Flutter release
echo ""
echo "[1/4] Building Flutter macOS release..."
cd "$PROJECT_DIR"
flutter build macos --release

APP_BUNDLE="$MACOS_BUILD_DIR/$APP_BUNDLE_NAME"
if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: Build failed — .app not found at $APP_BUNDLE"
    exit 1
fi
echo "  Build complete: $APP_BUNDLE"

# Step 2: Code sign (optional — ad-hoc if no identity)
echo ""
echo "[2/4] Code signing..."
if security find-identity -v -p codesigning 2>/dev/null | grep -q "[1-9] valid"; then
    IDENTITY=$(security find-identity -v -p codesigning | grep -m1 '"' | awk -F'"' '{print $2}')
    echo "  Signing with: $IDENTITY"
    codesign --deep --force --sign "$IDENTITY" "$APP_BUNDLE"
else
    echo "  No signing identity found — using ad-hoc signing"
    codesign --deep --force --sign - "$APP_BUNDLE"
fi
echo "  Signed."

# Step 3: Create DMG
echo ""
echo "[3/4] Creating .dmg..."
rm -rf "$DMG_DIR"
rm -f "$DMG_FILE"
mkdir -p "$DMG_DIR"

if command -v create-dmg &>/dev/null; then
    echo "  Using create-dmg..."
    create-dmg \
        --volname "$APP_DISPLAY_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_BUNDLE_NAME" 150 190 \
        --app-drop-link 450 190 \
        --hide-extension "$APP_BUNDLE_NAME" \
        "$DMG_FILE" \
        "$APP_BUNDLE" \
        2>/dev/null || {
            echo "  create-dmg failed, falling back to hdiutil..."
            build_dmg_simple
        }
else
    build_dmg_simple
fi

# Step 4: Verify
echo ""
echo "[4/4] Verifying..."
if [ -f "$DMG_FILE" ]; then
    echo ""
    echo "=== Done! ==="
    echo "DMG: $DMG_FILE"
    echo "Size: $(du -h "$DMG_FILE" | cut -f1)"
    echo ""
    echo "To install:"
    echo "  1. Open $DMG_FILE"
    echo "  2. Drag CopyPaste.app to Applications"
    echo ""
    echo "To distribute (notarize for Gatekeeper):"
    echo "  xcrun notarytool submit $DMG_FILE --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID"
else
    echo "ERROR: DMG not created"
    exit 1
fi

# Cleanup
rm -rf "$DMG_DIR"
