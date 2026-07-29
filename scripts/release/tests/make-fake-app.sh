#!/usr/bin/env bash
set -euo pipefail

# Создаёт минимальный валидный .app-бандл для тестов signing pipeline.
# Использование: make-fake-app.sh <out-dir>

if [[ $# -ne 1 ]]; then
    echo "Usage: ${0##*/} <out-dir>" >&2
    exit 1
fi

OUT_DIR="$1"
APP_DIR="$OUT_DIR/Fake.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

# Копируем /bin/echo как реальный Mach-O исполняемый файл и переименовываем в Fake.
cp -f /bin/echo "$APP_DIR/Contents/MacOS/Fake"
chmod +x "$APP_DIR/Contents/MacOS/Fake"

# Минимальный Info.plist: идентификатор тестового бандла и версия.
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.ascurse.MacLimitsTracker-test</string>
  <key>CFBundleShortVersionString</key><string>9.9.9</string>
  <key>CFBundleExecutable</key><string>Fake</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
PLIST

echo "$APP_DIR"
