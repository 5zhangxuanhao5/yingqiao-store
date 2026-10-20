#!/bin/bash
set -euo pipefail
stage=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$stage/build"
original_usb_flags=(-D YINGQIAO_LOCAL_EXTENSION_ONLY)
if [[ "${YQ_ORIGINAL_USB_TEST:-0}" == "1" ]]; then original_usb_flags+=(-D ORIGINAL_USB_TEST); fi
if [[ "${YQ_MAC_RECEIVER_PREVIEW:-0}" == "1" ]]; then original_usb_flags+=(-D MAC_RECEIVER_PREVIEW); fi
if [[ "${YQ_MAC_UNIFIED:-0}" == "1" ]]; then original_usb_flags+=(-D MAC_RECEIVER_ENABLED); fi
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
    -framework AppKit -framework Network -framework ScreenCaptureKit -framework VideoToolbox -framework AVFoundation -framework QuartzCore \
    "$usb/libYingqiaoUSB.a" -lc++ -framework IOUSBHost -framework IOKit -framework CoreGraphics -framework Security -framework CryptoKit -framework ApplicationServices \
    -o "$stage/build/YingqiaoStore-$arch"
done
app="$stage/build/映桥.app"
if [[ "${YQ_MAC_RECEIVER_PREVIEW:-0}" == "1" ]]; then app="$stage/build/映桥-Mac接屏测试.app"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "$stage/build/YingqiaoStore-arm64" "$stage/build/YingqiaoStore-x86_64" -output "$app/Contents/MacOS/YingqiaoStore"
cp "$stage/Info.plist" "$app/Contents/Info.plist"
if [[ "${YQ_MAC_RECEIVER_PREVIEW:-0}" == "1" ]]; then
 /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier cn.edgelink.macreceiver.preview' "$app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c 'Set :CFBundleName 映桥-Mac接屏测试' "$app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 映桥-Mac接屏测试' "$app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.4.0' "$app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 4' "$app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c 'Set :NSLocalNetworkUsageDescription 发现并连接你选择的另一台Mac，传送加密的扩展桌面。' "$app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c 'Add :NSBonjourServices:3 string _yqmacpreview._tcp' "$app/Contents/Info.plist"
fi
if [[ "${YQ_MAC_UNIFIED:-0}" == "1" ]]; then
 /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.4.0" "$app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 42" "$app/Contents/Info.plist"
 /usr/libexec/PlistBuddy -c "Add :NSBonjourServices:3 string _yqmacpreview._tcp" "$app/Contents/Info.plist"
fi
cp "$stage/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$stage/../third_party/lwip/COPYING" "$app/Contents/Resources/lwIP-LICENSE.txt"
# Local preview only. Public release requires Developer ID + notarization.
codesign --force --sign - "$app"
"$app/Contents/MacOS/YingqiaoStore" --self-test

if [[ "${YQ_MAC_RECEIVER_PREVIEW:-0}" == "1" ]]; then "$app/Contents/MacOS/YingqiaoStore" --mac-preview-self-test; fi

if [[ "${YQ_MAC_UNIFIED:-0}" == "1" ]]; then "$app/Contents/MacOS/YingqiaoStore" --mac-preview-self-test; fi
