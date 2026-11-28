#!/usr/bin/env bash
set -euo pipefail

# Packages WenBar.app (Release) into dist/WenBar-<VERSION>.dmg and dist/WenBar-<VERSION>.zip
# Usage:
#   bash scripts/package-dmg.sh 1.0.0
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" bash scripts/package-dmg.sh 1.0.0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${VERSION:-1.0.0}}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DEVELOPER_ID="${DEVELOPER_ID:--}"
TEAM_ID="${TEAM_ID:-}"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-}"

DIST_DIR="$ROOT_DIR/dist"
DERIVED_DATA="$ROOT_DIR/build/PackageDerivedData"
STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/WenBar-${VERSION}.dmg"
ZIP_PATH="$DIST_DIR/WenBar-${VERSION}.zip"

bash "$ROOT_DIR/scripts/setup-deps.sh"
cd "$ROOT_DIR"
xcodegen generate

rm -rf "$DIST_DIR"
mkdir -p "$STAGING_DIR"

IS_APPLE_DEV_ID=0
if [[ "$DEVELOPER_ID" == Developer\ ID\ Application:* ]]; then
  IS_APPLE_DEV_ID=1
fi

SIGN_EXTRA=()
if [ "$DEVELOPER_ID" = "-" ]; then
  SIGN_EXTRA+=(AD_HOC_CODE_SIGNING_ALLOWED=YES ENABLE_HARDENED_RUNTIME=NO)
elif [ "$IS_APPLE_DEV_ID" -eq 1 ]; then
  SIGN_EXTRA+=(ENABLE_HARDENED_RUNTIME=YES)
else
  # Persistent self-signed Code Signing identity keeps a fixed Designated Requirement across updates
  SIGN_EXTRA+=(ENABLE_HARDENED_RUNTIME=NO)
fi

if [ -n "$KEYCHAIN_PATH" ]; then
  SIGN_EXTRA+=(OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH")
fi

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
  "${SIGN_EXTRA[@]}" \
  build

APP_PATH="$STAGING_DIR/WenBar.app"
ditto "$DERIVED_DATA/Build/Products/Release/WenBar.app" "$APP_PATH"

if [ "$DEVELOPER_ID" != "-" ]; then
  CODESIGN_ARGS=(--force --sign "$DEVELOPER_ID")
  if [ -n "$KEYCHAIN_PATH" ]; then
    CODESIGN_ARGS+=(--keychain "$KEYCHAIN_PATH")
  fi
  if [ "$IS_APPLE_DEV_ID" -eq 1 ]; then
    echo "Applying Developer ID Hardened Runtime signature inside-out..."
    CODESIGN_ARGS+=(--options runtime --timestamp)
  else
    echo "Applying persistent Code Signing certificate inside-out..."
    CODESIGN_ARGS+=(--timestamp=none)
  fi

  codesign "${CODESIGN_ARGS[@]}" "$APP_PATH/Contents/Resources/bin/7zz"
  codesign "${CODESIGN_ARGS[@]}" \
    --entitlements "$ROOT_DIR/WenBarFinderSync/WenBarFinderSync.entitlements" \
    "$APP_PATH/Contents/PlugIns/WenBarFinderSync.appex"
  codesign "${CODESIGN_ARGS[@]}" \
    --entitlements "$ROOT_DIR/WenBar/WenBar.entitlements" \
    "$APP_PATH"
fi

codesign --verify --deep --strict "$APP_PATH"

ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/安装与首次打开说明.txt" <<'EOF'
WenBar 安装说明
================

1. 将左侧的 WenBar.app 拖入右侧 Applications（应用程序）文件夹。
2. 首次打开若遇到 macOS 提示“无法验证开发者”（未公证开源构建）：
   - 方式 A（推荐）：前往「系统设置 -> 隐私与安全性」，底部点击「仍要打开」。
   - 方式 B：在终端执行一次：
     xattr -dr com.apple.quarantine /Applications/WenBar.app
3. 拖入 /Applications 安装完成后，后续所有版本均可直接在软件内点击「检查更新 -> 下载并安装重启」，自动完成覆盖安装、清除隔离属性并重启，无需再次手动操作！
EOF

echo "Creating ZIP archive for fast in-app auto-update..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Creating DMG installer..."
hdiutil create -volname "WenBar ${VERSION}" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "Packages ready:"
ls -lh "$DMG_PATH" "$ZIP_PATH"
