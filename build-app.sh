#!/bin/zsh
# Builds Desktop Buddy.app (release) into ./dist and optionally installs it to ~/Applications.
#   ./build-app.sh            build only
#   ./build-app.sh --install  build and copy to ~/Applications, then launch
#   ./build-app.sh --share    build a .zip and .dmg in ./dist to send to teammates
#
# If ./team.json exists it is bundled, so teammates never need OAuth client IDs.
# Set SIGN_ID="Developer ID Application: Your Co (TEAMID)" to sign for distribution;
# otherwise the app is ad-hoc signed (teammates right-click → Open the first time).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

# Scenario tests (temp data folder, no Keychain, no network to Google/Microsoft). Any failure stops the build.
TEST_HOME=$(mktemp -d)
if ! DESKTOPBUDDY_HOME="$TEST_HOME" .build/release/DesktopBuddyV2 --selftest > "$TEST_HOME/selftest.log" 2>&1; then
  cat "$TEST_HOME/selftest.log"; echo "Self-test failed, not packaging."; exit 1
fi
tail -1 "$TEST_HOME/selftest.log"; rm -rf "$TEST_HOME"
APP="dist/Desktop Buddy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DesktopBuddyV2 "$APP/Contents/MacOS/DesktopBuddyV2"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Logos "$APP/Contents/Resources/Logos"
if [[ -f team.json ]]; then cp team.json "$APP/Contents/Resources/team.json"; echo "Bundled team.json"; fi

# A Google client with no secret (iOS type) returns to the app's own URL scheme, so register it.
URL_TYPES=""
if [[ -f team.json ]]; then
  GOOGLE_ID=$(plutil -extract googleClientID raw -o - team.json 2>/dev/null || true)
  GSECRET=$(plutil -extract googleClientSecret raw -o - team.json 2>/dev/null || true)
  if [[ -n "$GOOGLE_ID" && -z "$GSECRET" ]]; then
    SUFFIX=".apps.googleusercontent.com"
    SCHEME="com.googleusercontent.apps.${GOOGLE_ID%"$SUFFIX"}"
    URL_TYPES="<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Google sign-in</string><key>CFBundleURLSchemes</key><array><string>${SCHEME}</string></array></dict></array>"
  fi
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Desktop Buddy</string>
  <key>CFBundleDisplayName</key><string>Desktop Buddy</string>
  <key>CFBundleIdentifier</key><string>com.desktopbuddy.v2</string>
  <key>CFBundleExecutable</key><string>DesktopBuddyV2</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>2.2</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>NSHumanReadableCopyright</key><string>Desktop Buddy. Reads Google Workspace and Microsoft 365 on your Mac; no servers, no AI.</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  $URL_TYPES
</dict></plist>
PLIST

if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
echo "Built: $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications"
  [[ -w "$DEST" ]] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
  pkill -x DesktopBuddyV2 2>/dev/null || true
  rm -rf "$HOME/Applications/Desktop Buddy.app" "$DEST/Desktop Buddy.app"
  cp -R "$APP" "$DEST/"
  open "$DEST/Desktop Buddy.app"
  echo "Installed to $DEST and launched."
fi

if [[ "${1:-}" == "--share" ]]; then
  rm -f "dist/Desktop Buddy.zip" "dist/Desktop Buddy.dmg"
  ditto -c -k --keepParent "$APP" "dist/Desktop Buddy.zip"
  STAGE=$(mktemp -d)
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Desktop Buddy" -srcfolder "$STAGE" -ov -format UDZO "dist/Desktop Buddy.dmg" >/dev/null
  rm -rf "$STAGE"
  echo "Share: $PWD/dist/Desktop Buddy.dmg (and .zip)"
fi
