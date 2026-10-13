#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="AleCal"
APP_BUNDLE="${DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"

echo "🎨 Generating AppIcon.icns from Assets.xcassets..."
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
cp "${DIR}/Resources/Assets.xcassets/AppIcon.appiconset"/*.png "$ICONSET_DIR/"
iconutil -c icns "$ICONSET_DIR" -o "${DIR}/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_DIR")"

echo "🔨 Compiling release binary with swiftc..."
mkdir -p "${MACOS}" "${RESOURCES}"
swiftc -sdk "${SDK_PATH}" \
       -target arm64-apple-macos14.0 \
       -O \
       -parse-as-library \
       "${DIR}/Sources"/*.swift \
       -o "${MACOS}/${APP_NAME}"

chmod +x "${MACOS}/${APP_NAME}"

echo "📦 Packaging ${APP_NAME}.app..."
cp "${DIR}/Resources/AppIcon.icns" "${RESOURCES}/AppIcon.icns"
cp "${DIR}/Resources/Info.plist" "${CONTENTS}/Info.plist"

if [ -d "${DIR}/Resources/en.lproj" ]; then
    cp -R "${DIR}/Resources/en.lproj" "${RESOURCES}/"
fi
if [ -d "${DIR}/Resources/tr.lproj" ]; then
    cp -R "${DIR}/Resources/tr.lproj" "${RESOURCES}/"
fi

# Strip quarantine and sign with ad-hoc signature
xattr -cr "${APP_BUNDLE}"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✅ Successfully built and signed ${APP_BUNDLE}!"

# Setup DMG staging with Applications symlink
STAGING_DIR="${DIR}/.dmg_staging"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

cp -R "${APP_BUNDLE}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

if [ -f "${DIR}/Resources/AppIcon.icns" ]; then
    cp "${DIR}/Resources/AppIcon.icns" "${STAGING_DIR}/.VolumeIcon.icns"
fi

# Create macOS DMG image
DMG_PATH="${DIR}/${APP_NAME}.dmg"
rm -f "${DMG_PATH}"
echo "💿 Creating ${APP_NAME}.dmg with Applications drag-and-drop link..."
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_PATH}" -quiet
rm -rf "${STAGING_DIR}"

# Remove quarantine from DMG
xattr -cr "${DMG_PATH}"
echo "✅ Successfully built DMG at ${DMG_PATH}!"

# Install to /Applications
INSTALL_PATH="/Applications/${APP_NAME}.app"
echo "🚀 Installing to ${INSTALL_PATH}..."
pkill -x "${APP_NAME}" 2>/dev/null || true
rm -rf "${INSTALL_PATH}"
cp -R "${APP_BUNDLE}" "${INSTALL_PATH}"
xattr -cr "${INSTALL_PATH}"
touch "${INSTALL_PATH}"

echo "🎉 Installed ${APP_NAME}.app to /Applications successfully!"
