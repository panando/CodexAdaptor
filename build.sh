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

# ── Signing and release checks ────────────────────────────────
echo "==> Fixing Swift runtime rpaths..."
BINARY_PATH="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
FRAMEWORKS_DIR="${APP_BUNDLE}/Contents/Frameworks"
XCODE_SWIFT_RPATH=$(otool -l "${BINARY_PATH}" | sed -n 's/^ *path \(\/Applications\/Xcode\.app\/.*\/usr\/lib\/swift-[^ ]*\/macosx\) (offset.*$/\1/p' | head -n 1)

if [ -n "${XCODE_SWIFT_RPATH}" ]; then
    mkdir -p "${FRAMEWORKS_DIR}"
    if [ ! -f "${XCODE_SWIFT_RPATH}/libswiftCompatibilitySpan.dylib" ]; then
        echo "ERROR: missing Swift compatibility library: ${XCODE_SWIFT_RPATH}/libswiftCompatibilitySpan.dylib" >&2
        exit 1
    fi
    cp "${XCODE_SWIFT_RPATH}/libswiftCompatibilitySpan.dylib" "${FRAMEWORKS_DIR}/"
    if ! otool -l "${BINARY_PATH}" | grep -q '@executable_path/../Frameworks'; then
        install_name_tool -add_rpath "@executable_path/../Frameworks" "${BINARY_PATH}"
    fi
    install_name_tool -delete_rpath "${XCODE_SWIFT_RPATH}" "${BINARY_PATH}"
fi

echo "==> Ad-hoc signing app bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"

./verify-release.sh "${APP_BUNDLE}"

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

echo "==> Verifying DMG contents..."
MOUNT_DIR=$(mktemp -d)
hdiutil attach "${DMG_NAME}" -mountpoint "${MOUNT_DIR}" -nobrowse -readonly >/dev/null
cleanup_mount() {
    hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 || true
    rmdir "${MOUNT_DIR}" 2>/dev/null || true
}
trap cleanup_mount EXIT
./verify-release.sh "${MOUNT_DIR}/${APP_BUNDLE}"
cleanup_mount
trap - EXIT

echo ""
echo "Done: ${DMG_NAME}"
echo "App bundle: ${APP_BUNDLE}"
