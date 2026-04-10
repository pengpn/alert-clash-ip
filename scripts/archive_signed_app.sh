#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AlertClashIP.xcodeproj"
SCHEME="AlertClashIP"
ARCHIVE_PATH="$ROOT_DIR/dist/AlertClashIP.xcarchive"
EXPORT_DIR="$ROOT_DIR/dist/export"
EXPORT_OPTIONS_PLIST="$ROOT_DIR/SupportingFiles/ExportOptions-DeveloperID.plist"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild 不可用。请先安装完整 Xcode，并执行 xcode-select 切换到 Xcode。" >&2
  exit 1
fi

if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
  echo "error: 缺少导出配置 $EXPORT_OPTIONS_PLIST" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/dist"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

echo "==> Archiving app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo "==> Exporting signed app"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

echo "==> Exported files:"
echo "$EXPORT_DIR"
