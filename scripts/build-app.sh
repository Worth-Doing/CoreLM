#!/bin/bash
set -euo pipefail

# CoreLM Build Script — creates signed .app bundle + DMG
# Usage: ./scripts/build-app.sh

PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJ_ROOT/apps/CoreLMApp"
ENGINE_DIR="$PROJ_ROOT/engine"
RESOURCES="$APP_DIR/Resources"
BUILD_OUT="$PROJ_ROOT/build"

IDENTITY="Developer ID Application: Simon-Pierre Boucher (3YM54G49SN)"
TEAM_ID="3YM54G49SN"
BUNDLE_ID="com.corelm.app"

APP_NAME="CoreLM"
APP_BUNDLE="$BUILD_OUT/$APP_NAME.app"

echo "=== CoreLM Build ==="
echo ""

# ── 1. Build engine ──────────────────────────────────────────
echo "[1/5] Building engine..."
cd "$ENGINE_DIR"
make clean >/dev/null 2>&1 || true
make lib 2>&1 | tail -1
echo "      Engine built."

# ── 2. Build Swift app (release) ─────────────────────────────
echo "[2/5] Building Swift app (release)..."
cd "$APP_DIR"
swift build -c release 2>&1 | tail -1
SWIFT_BIN=$(swift build -c release --show-bin-path 2>/dev/null)/CoreLMApp
echo "      Swift binary: $SWIFT_BIN"

# ── 3. Assemble .app bundle ─────────────────────────────────
echo "[3/5] Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$SWIFT_BIN" "$APP_BUNDLE/Contents/MacOS/CoreLMApp"

# Copy Info.plist
cp "$RESOURCES/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy icon
cp "$RESOURCES/CoreLM.icns" "$APP_BUNDLE/Contents/Resources/CoreLM.icns"

# Copy Metal shaders source (for runtime compilation)
cp "$ENGINE_DIR/metal/kernels.metal" "$APP_BUNDLE/Contents/Resources/kernels.metal"

# Write PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "      App bundle: $APP_BUNDLE"

# ── 4. Code sign ─────────────────────────────────────────────
echo "[4/5] Code signing..."
codesign --force --deep --options runtime \
    --sign "$IDENTITY" \
    --entitlements "$RESOURCES/CoreLM.entitlements" \
    --timestamp \
    "$APP_BUNDLE" 2>&1

codesign --verify --verbose "$APP_BUNDLE" 2>&1
echo "      Signed successfully."

# ── 5. Create DMG ────────────────────────────────────────────
echo "[5/5] Creating DMG..."
DMG_PATH="$BUILD_OUT/$APP_NAME.dmg"
DMG_TMP="$BUILD_OUT/dmg_staging"
rm -rf "$DMG_TMP" "$DMG_PATH"
mkdir -p "$DMG_TMP"

cp -R "$APP_BUNDLE" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TMP" \
    -ov -format UDZO \
    "$DMG_PATH" 2>&1

rm -rf "$DMG_TMP"

# Sign the DMG too
codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH" 2>&1

echo "      DMG: $DMG_PATH"

echo ""
echo "=== Build complete ==="
echo "  App: $APP_BUNDLE"
echo "  DMG: $DMG_PATH"
echo ""
echo "To notarize, run:"
echo "  xcrun notarytool submit $DMG_PATH --apple-id spbou4@icloud.com --team-id $TEAM_ID --password <app-password> --wait"
echo "  xcrun stapler staple $DMG_PATH"
