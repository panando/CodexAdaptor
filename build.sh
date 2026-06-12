#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="CodexAdaptor"
BINARY_NAME="CodexRouterApp"
VERSION=$(cat VERSION)
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
APP_BUNDLE="${APP_NAME}.app"

echo "==> Building ${APP_NAME} v${VERSION}..."

# Build release binary
swift build -c release

# ── App bundle ────────────────────────────────────────────────
echo "==> Creating .app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Binary
cp ".build/release/${BINARY_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Icon
cp "CodexAdaptor.icns" "${APP_BUNDLE}/Contents/Resources/"

# Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.codexadaptor.app</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>CodexAdaptor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# ── DMG ───────────────────────────────────────────────────────
echo "==> Creating DMG..."
rm -f "${DMG_NAME}"

# Create a staging directory for the DMG
STAGING="dmg_staging"
rm -rf "${STAGING}"
mkdir "${STAGING}"
cp -R "${APP_BUNDLE}" "${STAGING}/"
# Symlink to /Applications for drag-to-install
ln -s /Applications "${STAGING}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

rm -rf "${STAGING}"

echo ""
echo "Done: ${DMG_NAME}"
echo "App bundle: ${APP_BUNDLE}"
