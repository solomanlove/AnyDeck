#!/bin/bash
# macOS/iOS 15 USB 视频 PoC：复用生产采集器，默认只列出采集设备。
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
poc_dir="$(mktemp -d "${TMPDIR:-/tmp}/anydeck-ios-usb.XXXXXX")"
trap 'rm -rf "$poc_dir"' EXIT
xcrun swiftc "$repo_dir/macos/Runner/IosUsbCapture.swift" \
  "$repo_dir/tool/ios_usb_poc/main.swift" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
  -Xlinker "$repo_dir/tool/ios_usb_poc/Info.plist" -o "$poc_dir/ios-usb-poc"
"$poc_dir/ios-usb-poc" "${1:---list}" "${2:-10}"
