#!/bin/bash
# 编译并打包成 NotchTodo.app（可拖到「应用程序」并设为登录启动）
set -e
cd "$(dirname "$0")"
swift build -c release

APP="NotchTodo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/NotchTodo "$APP/Contents/MacOS/NotchTodo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NotchTodo</string>
  <key>CFBundleIdentifier</key><string>com.majunze.NotchTodo</string>
  <key>CFBundleExecutable</key><string>NotchTodo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"   # 本地 ad-hoc 签名
echo "✅ 已生成 $(pwd)/$APP"
