#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/WenBar/Resources/bin"
TARGET_7ZZ="$BIN_DIR/7zz"

mkdir -p "$BIN_DIR"

if ! command -v brew >/dev/null 2>&1; then
  echo "Error: Homebrew is required to install xcodegen and sevenzip." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing xcodegen..."
  brew install xcodegen
fi

if ! command -v 7zz >/dev/null 2>&1; then
  echo "Installing sevenzip..."
  brew install sevenzip
fi

SRC_7ZZ="$(command -v 7zz)"
cp -f "$SRC_7ZZ" "$TARGET_7ZZ"
chmod +x "$TARGET_7ZZ"

echo "Bundled 7zz at: $TARGET_7ZZ"
otool -L "$TARGET_7ZZ"
