#!/bin/bash
set -e

echo "=== CoreLM Build Script ==="
echo ""

# Configuration
APP_NAME="CoreLM"
BUNDLE_ID="com.simonpierreboucher.CoreLM"
BUILD_DIR=".build"
VERSION="1.0.0"
SIGNING_IDENTITY="Developer ID Application: Simon-Pierre Boucher (3YM54G49SN)"
TEAM_ID="3YM54G49SN"
APPLE_ID="spbou4@icloud.com"
APP_PASSWORD="kmnu-cmfc-txwl-deuy"

# Step 1: Build release
echo "[1/7] Building $APP_NAME (release)..."
swift build -c release 2>&1

# Step 2: Create .app bundle
echo "[2/7] Creating app bundle..."
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Copy icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    echo "   Icon copied."
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSLocalNetworkUsageDescription</key>
    <string>CoreLM runs a local API server for AI model integration.</string>
</dict>
</plist>
PLIST

# Create entitlements
cat > "entitlements.plist" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Step 3: Code sign
echo "[3/7] Code signing..."
codesign --force --options runtime \
    --entitlements entitlements.plist \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "$APP_DIR"

# Verify signature
echo "   Verifying signature..."
codesign --verify --verbose=2 "$APP_DIR" 2>&1
echo "   Signature OK."

# Step 4: Create DMG
echo "[4/7] Creating DMG..."
DMG_NAME="${APP_NAME}-${VERSION}"
DMG_FILE="${DMG_NAME}.dmg"
DMG_STAGING="/tmp/coreLM_dmg_$$"

rm -rf "$DMG_STAGING" "$DMG_FILE"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Create hybrid ISO then convert to UDIF DMG
DMG_HYBRID="/tmp/${DMG_NAME}_hybrid_$$.dmg"
hdiutil makehybrid -o "$DMG_HYBRID" "$DMG_STAGING" \
    -hfs \
    -hfs-volume-name "$APP_NAME" \
    -default-volume-name "$APP_NAME" 2>&1

# Convert to proper UDIF format (required for notarization)
hdiutil convert "$DMG_HYBRID" -format UDZO -o "$DMG_FILE" 2>&1

rm -rf "$DMG_STAGING" "$DMG_HYBRID"

# Step 5: Sign DMG
echo "[5/7] Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_FILE"
echo "   DMG signed."

# Step 6: Notarize
echo "[6/7] Notarizing with Apple..."
echo "   Submitting to Apple notary service..."
xcrun notarytool submit "$DMG_FILE" \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait 2>&1

# Step 7: Staple
echo "[7/7] Stapling notarization ticket..."
xcrun stapler staple "$DMG_FILE" 2>&1

echo ""
echo "============================================"
echo "  BUILD COMPLETE!"
echo "============================================"
echo ""
echo "  App:  $APP_DIR"
echo "  DMG:  $DMG_FILE"
echo "  Signed by: $SIGNING_IDENTITY"
echo "  Notarized: Yes"
echo ""
echo "  Users can install by opening the DMG"
echo "  and dragging CoreLM to Applications."
echo ""
echo "=== CoreLM — Local AI, Perfected. ==="
