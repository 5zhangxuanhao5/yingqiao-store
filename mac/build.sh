#!/bin/bash
set -euo pipefail
stage=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$stage/build"
for arch in arm64 x86_64; do
  swiftc -j 4 -O -whole-module-optimization -swift-version 5 -target "$arch-apple-macos13.0" \
    -import-objc-header "$stage/Sources/CGVirtualDisplayPrivate.h" "$stage/Sources/"*.swift \
    -framework AppKit -framework Network -framework ScreenCaptureKit -framework VideoToolbox \
    -framework CoreGraphics -framework Security -framework CryptoKit -framework ApplicationServices \
    -o "$stage/build/YingqiaoStore-$arch"
done
app="$stage/build/映桥测试版.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "$stage/build/YingqiaoStore-arm64" "$stage/build/YingqiaoStore-x86_64" -output "$app/Contents/MacOS/YingqiaoStore"
cp "$stage/Info.plist" "$app/Contents/Info.plist"
cp "$stage/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
# Local preview only. Public release requires Developer ID + notarization.
codesign --force --sign - "$app"
"$app/Contents/MacOS/YingqiaoStore" --self-test
