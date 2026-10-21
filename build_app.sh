#!/bin/bash
# 编译并打包为 NotchTodo.app 和 NotchTodo.zip
set -e
cd "$(dirname "$0")"
VERSION="${1:-1.0.0}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NotchTodo"
[ -f "$BIN" ] || { echo "❌ 找不到编译产物：$BIN"; exit 1; }

APP="NotchTodo.app"
rm -rf "$APP" NotchTodo.zip
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/NotchTodo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NotchTodo</string>
  <key>CFBundleIdentifier</key><string>com.majunze.NotchTodo</string>
  <key>CFBundleExecutable</key><string>NotchTodo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
ditto -c -k --keepParent "$APP" NotchTodo.zip
echo "✅ 已生成 $APP 和 NotchTodo.zip（版本 $VERSION）"
