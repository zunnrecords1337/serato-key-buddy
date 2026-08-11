#!/bin/bash
# Build a universal (Intel + Apple Silicon) .app bundle and a distributable .dmg.
set -euo pipefail

APP_NAME="SeratoKeyBuddy"
DISPLAY_NAME="Serato Key Buddy"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

cd "$ROOT"

echo "==> Building x86_64"
swift build -c release --arch x86_64 --build-path .build-x86

echo "==> Building arm64"
swift build -c release --arch arm64 --build-path .build-arm

echo "==> Creating universal binary"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS"
lipo -create \
  ".build-x86/release/$APP_NAME" \
  ".build-arm/release/$APP_NAME" \
  -output "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.zunn.$APP_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Creating DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DIST/$APP_NAME.dmg" >/dev/null
rm -rf "$STAGE"

echo "==> Done"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"
ls -lh "$DIST/$APP_NAME.dmg"
