#!/bin/bash
set -euo pipefail
stage=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$stage/build"
original_usb_flags=(-D YINGQIAO_LOCAL_EXTENSION_ONLY)
if [[ "${YQ_ORIGINAL_USB_TEST:-0}" == "1" ]]; then original_usb_flags+=(-D ORIGINAL_USB_TEST); fi
for arch in arm64 x86_64; do
  usb="$stage/build/usb-$arch"
  mkdir -p "$usb"
  lwip="$stage/../third_party/lwip/src"
  objects=()
  for source in "$lwip/core/"*.c "$lwip/core/ipv4/"*.c "$lwip/netif/ethernet.c"; do
    object="$usb/$(basename "$source" .c).o"
    clang -target "$arch-apple-macos13.0" -O2 -I"$stage/USB/port" -I"$lwip/include" -c "$source" -o "$object"
    objects+=("$object")
  done
  clang++ -target "$arch-apple-macos13.0" -std=c++17 -O2 -fobjc-arc -I"$stage/USB/port" -I"$lwip/include" -c "$stage/USB/StoreUSB.mm" -o "$usb/StoreUSB.o"
  objects+=("$usb/StoreUSB.o")
  libtool -static -o "$usb/libYingqiaoUSB.a" "${objects[@]}"

  swiftc "${original_usb_flags[@]}" -j 4 -O -whole-module-optimization -swift-version 5 -target "$arch-apple-macos13.0" \
    -import-objc-header "$stage/Sources/CGVirtualDisplayPrivate.h" "$stage/Sources/"*.swift \
    -framework AppKit -framework Network -framework ScreenCaptureKit -framework VideoToolbox \
    "$usb/libYingqiaoUSB.a" -lc++ -framework IOUSBHost -framework IOKit -framework CoreGraphics -framework Security -framework CryptoKit -framework ApplicationServices \
    -o "$stage/build/YingqiaoStore-$arch"
done
app="$stage/build/映桥.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "$stage/build/YingqiaoStore-arm64" "$stage/build/YingqiaoStore-x86_64" -output "$app/Contents/MacOS/YingqiaoStore"
cp "$stage/Info.plist" "$app/Contents/Info.plist"
cp "$stage/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$stage/../third_party/lwip/COPYING" "$app/Contents/Resources/lwIP-LICENSE.txt"
# Local preview only. Public release requires Developer ID + notarization.
codesign --force --sign - "$app"
"$app/Contents/MacOS/YingqiaoStore" --self-test
