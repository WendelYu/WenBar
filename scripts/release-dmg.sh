#!/usr/bin/env bash
set -euo pipefail

# WenBar Release Build, Hardened Runtime Signing, Apple Notarization, DMG & Sparkle Appcast Template
# Usage:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="wenbar-notary" \
#   VERSION="1.0.0" \
#   bash scripts/release-dmg.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
TEAM_ID="${TEAM_ID:-}"
SPARKLE_DOWNLOAD_BASE_URL="${SPARKLE_DOWNLOAD_BASE_URL:-https://github.com/example/WenBar/releases/download/v${VERSION}}"

DIST_DIR="$ROOT_DIR/dist"
DERIVED_DATA="$ROOT_DIR/build/ReleaseDerivedData"
STAGING_DIR="$DIST_DIR/staging"
DMG_PATH="$DIST_DIR/WenBar-${VERSION}.dmg"
APPCAST_PATH="$DIST_DIR/appcast.xml"

if [ -z "$DEVELOPER_ID" ]; then
  echo "Error: DEVELOPER_ID is required, e.g. 'Developer ID Application: Name (TEAMID)'" >&2
  exit 1
fi

bash "$ROOT_DIR/scripts/setup-deps.sh"
cd "$ROOT_DIR"
xcodegen generate

rm -rf "$DIST_DIR"
mkdir -p "$STAGING_DIR"

xcodebuild \
  -project "$ROOT_DIR/WenBar.xcodeproj" \
  -scheme WenBar \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  build

APP_PATH="$STAGING_DIR/WenBar.app"
ditto "$DERIVED_DATA/Build/Products/Release/WenBar.app" "$APP_PATH"

echo "Signing embedded binaries inside-out..."
if [ -f "$APP_PATH/Contents/Resources/bin/7zz" ]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_PATH/Contents/Resources/bin/7zz"
fi

if [ -d "$APP_PATH/Contents/PlugIns/WenBarFinderSync.appex" ]; then
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT_DIR/WenBarFinderSync/WenBarFinderSync.entitlements" \
    --sign "$DEVELOPER_ID" \
    "$APP_PATH/Contents/PlugIns/WenBarFinderSync.appex"
fi

codesign --force --options runtime --timestamp \
  --entitlements "$ROOT_DIR/WenBar/WenBar.entitlements" \
  --sign "$DEVELOPER_ID" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "WenBar" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG_PATH"

if [ -n "$NOTARY_PROFILE" ]; then
  echo "Submitting DMG for Apple Notarization..."
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "Skipping notarization (NOTARY_PROFILE not set)."
fi

DMG_SIZE=$(stat -f%z "$DMG_PATH")
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>WenBar Updates</title>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="${SPARKLE_DOWNLOAD_BASE_URL}/WenBar-${VERSION}.dmg"
                 length="${DMG_SIZE}"
                 type="application/octet-stream"
                 sparkle:edSignature="REPLACE_WITH_SIGN_UPDATE_SIGNATURE" />
    </item>
  </channel>
</rss>
EOF

echo "Release artifacts ready:"
echo "  DMG:     $DMG_PATH"
echo "  Appcast: $APPCAST_PATH"
