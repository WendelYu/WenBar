#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-Debug}"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_OUT_DIR="$ROOT_DIR/build/$CONFIG"

bash "$ROOT_DIR/scripts/setup-deps.sh"

cd "$ROOT_DIR"
xcodegen generate

xcodebuild \
  -project "$ROOT_DIR/WenBar.xcodeproj" \
  -scheme WenBar \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIG/WenBar.app"
mkdir -p "$APP_OUT_DIR"
rm -rf "$APP_OUT_DIR/WenBar.app"
ditto "$BUILT_APP" "$APP_OUT_DIR/WenBar.app"

echo "Verifying bundle signature..."
codesign --verify --deep --strict "$APP_OUT_DIR/WenBar.app"

APPEX_PATH="$APP_OUT_DIR/WenBar.app/Contents/PlugIns/WenBarFinderSync.appex"
if [ -d "$APPEX_PATH" ]; then
  echo "Registering FinderSync extension via pluginkit..."
  pluginkit -a "$APPEX_PATH" || true
  pluginkit -e use -i com.wenbar.app.FinderSync || true
fi

echo "Build complete: $APP_OUT_DIR/WenBar.app"
