#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Tidebar"
BIN_NAME="Tidebar"
DIST_DIR="$SCRIPT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP_FILE="$DIST_DIR/$APP_NAME-mac.zip"

echo "=== [1/5] 清理并准备构建目录 ==="
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/build"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

SWIFTC_CMD="swiftc"
if command -v xcrun &>/dev/null; then
  SWIFTC_CMD="xcrun swiftc"
fi

SDK_FLAG=""
if command -v xcrun &>/dev/null && xcrun --show-sdk-path &>/dev/null; then
  SDK_PATH="$(xcrun --show-sdk-path)"
  SDK_FLAG="-sdk $SDK_PATH"
elif [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" ]; then
  SDK_FLAG="-sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
fi

SOURCES=(
  Sources/*.swift
  Sources/Modules/*.swift
)

echo "=== [2/5] 编译 arm64 架构 ==="
$SWIFTC_CMD -O -swift-version 5 -target arm64-apple-macos13 $SDK_FLAG \
  -o "$DIST_DIR/build/${BIN_NAME}_arm64" "${SOURCES[@]}"

echo "=== [3/5] 编译 x86_64 架构 ==="
$SWIFTC_CMD -O -swift-version 5 -target x86_64-apple-macos13 $SDK_FLAG \
  -o "$DIST_DIR/build/${BIN_NAME}_x86_64" "${SOURCES[@]}"

echo "=== [4/5] 使用 lipo 合并为通用二进制 (Universal Binary) ==="
lipo -create -output "$APP_BUNDLE/Contents/MacOS/$BIN_NAME" \
  "$DIST_DIR/build/${BIN_NAME}_arm64" \
  "$DIST_DIR/build/${BIN_NAME}_x86_64"

# 拷贝 Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 若存在 icon.png 则生成 AppIcon.icns
if [ -f "$SCRIPT_DIR/icon.png" ]; then
  echo "  生成应用图标 AppIcon.icns..."
  ICONSET="$DIST_DIR/build/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for sz in 16 32 128 256 512; do
    sips -z $sz $sz "$SCRIPT_DIR/icon.png" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null 2>&1 || true
    sips -z $((sz*2)) $((sz*2)) "$SCRIPT_DIR/icon.png" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null 2>&1 || true
  done
  iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi

# 清理中间构件
rm -rf "$DIST_DIR/build"

echo "=== [5/5] Ad-hoc 签名与打包 ==="
xattr -cr "$APP_BUNDLE"
codesign --force --sign - "$APP_BUNDLE"

ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_FILE"

echo "✅ 构建完成！"
echo "  应用包：$APP_BUNDLE"
echo "  发布包：$ZIP_FILE"
