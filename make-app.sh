#!/usr/bin/env bash
set -euo pipefail

# Создаёт MacLimitsTracker.app из swift build -c release.
# Использование: ./make-app.sh [output-dir]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$ROOT/dist}"
APP_NAME="MacLimitsTracker"
APP_DIR="$OUT_DIR/$APP_NAME.app"

# BIN_SRC можно передать извне (например, universal-бинарь из
# `swift build -c release --arch arm64 --arch x86_64`, который лежит в
# .build/apple/Products/Release). Иначе собираем обычный release.
if [[ -z "${BIN_SRC:-}" ]]; then
  echo "Building release binary..."
  swift build -c release
  BIN_SRC="$ROOT/.build/release/$APP_NAME"
fi
if [[ ! -x "$BIN_SRC" ]]; then
  echo "Build output not found at $BIN_SRC" >&2
  exit 1
fi

echo "Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_SRC" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacLimitsTracker</string>
  <key>CFBundleDisplayName</key><string>Limits Tracker</string>
  <key>CFBundleIdentifier</key><string>dev.ascurse.MacLimitsTracker</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>MacLimitsTracker</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "Done: $APP_DIR"
echo "Run with: open \"$APP_DIR\""