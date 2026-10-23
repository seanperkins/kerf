#!/bin/zsh
# Builds LoftLine in release mode and wraps it into dist/LoftLine.app (ad-hoc signed).
# Usage: scripts/bundle.sh [--debug]
set -euo pipefail
cd "${0:A:h}/.."
CONFIG=release
[[ "${1:-}" == "--debug" ]] && CONFIG=debug
source scripts/swiftpm-env.sh
swift build "${SWIFTPM_FLAGS[@]}" -c $CONFIG --product LoftLine
BIN="$(swift build "${SWIFTPM_FLAGS[@]}" -c $CONFIG --show-bin-path)/LoftLine"
APP=dist/LoftLine.app
VERSION=$(git describe --tags --always 2>/dev/null || echo 0.1)
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp "$BIN" $APP/Contents/MacOS/LoftLine
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns $APP/Contents/Resources/
# Sample files opened from the Welcome window.
mkdir -p $APP/Contents/Resources/samples
cp samples/*.loftline samples/*.svg samples/*.dxf samples/*.stl $APP/Contents/Resources/samples/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LoftLine</string>
  <key>CFBundleDisplayName</key><string>LoftLine</string>
  <key>CFBundleIdentifier</key><string>com.seanperkins.loftline</string>
  <key>CFBundleExecutable</key><string>LoftLine</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>LoftLine Project</string>
      <key>CFBundleTypeExtensions</key><array><string>loftline</string></array>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>com.seanperkins.loftline.project</string></array>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>com.seanperkins.loftline.project</string>
      <key>UTTypeDescription</key><string>LoftLine Project</string>
      <key>UTTypeConformsTo</key><array><string>public.json</string><string>public.data</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key><array><string>loftline</string></array>
        <key>public.mime-type</key><string>application/x-loftline+json</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST
# Quick Look thumbnail extension (io-file-thumbnails): built with swiftc, since SwiftPM cannot
# make an .appex. It must be sandboxed, so it is signed with its own entitlements before the app.
# LOFTLINE_NO_QL_EXTENSION=1 skips it.
if [[ -z "${LOFTLINE_NO_QL_EXTENSION:-}" ]]; then
  APPEX=$APP/Contents/PlugIns/LoftLineThumbnail.appex
  mkdir -p $APPEX/Contents/MacOS
  OPT=-O; [[ $CONFIG == debug ]] && OPT=-Onone
  swiftc $OPT -module-name LoftLineThumbnail -parse-as-library -application-extension \
    -target "$(uname -m)-apple-macos14.0" -Xlinker -e -Xlinker _NSExtensionMain \
    -framework QuickLookThumbnailing \
    Extensions/QuickLookThumbnail/ThumbnailProvider.swift Sources/LoftLineApp/Model/QuickLookThumbnailData.swift \
    -o $APPEX/Contents/MacOS/LoftLineThumbnail
  sed "s/__VERSION__/${VERSION}/" Extensions/QuickLookThumbnail/Info.plist > $APPEX/Contents/Info.plist
  codesign -s - --force --entitlements Extensions/QuickLookThumbnail/LoftLineThumbnail.entitlements $APPEX
fi
codesign -s - --force $APP
echo "Built $APP"
