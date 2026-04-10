#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AlertClashIP.xcodeproj"
SCHEME="AlertClashIP"
DERIVED_DATA_PATH="$ROOT_DIR/.build/xcode-derived-data"
OUTPUT_DIR="$ROOT_DIR/dist"
APP_NAME="AlertClashIP.app"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild 不可用。请先安装完整 Xcode，并执行 xcode-select 切换到 Xcode。" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$DERIVED_DATA_PATH"

echo "==> Building Release app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_SOURCE="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME"
APP_DEST="$OUTPUT_DIR/$APP_NAME"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "error: 未找到构建产物 $APP_SOURCE" >&2
  exit 1
fi

rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"

echo "==> Built app:"
echo "$APP_DEST"
