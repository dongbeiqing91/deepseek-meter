#!/bin/bash
# 组装可运行的 .app（无 Xcode，用 SwiftPM 产物 + 手写 Info.plist + ad-hoc 签名）
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="DeepSeek Meter"
APP="build/$APP_NAME.app"

echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/DeepSeekMeter"
[ -f "$BIN" ] || { echo "找不到可执行文件 $BIN"; exit 1; }

echo "▸ 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DeepSeekMeter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ ad-hoc 签名"
codesign --force --sign - --timestamp=none "$APP" >/dev/null

echo "▸ 完成：$(pwd)/$APP"
codesign -dv "$APP" 2>&1 | sed -n '1,3p'
