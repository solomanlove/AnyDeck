#!/bin/bash
# 编译并运行原生摄像头状态/像素测试；不启动 AnyDeck、不激活 Extension、不访问真实镜头。
set -euo pipefail
cd "$(dirname "$0")/.."
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/anydeck-camera-tests.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
arch=$(uname -m)
xcrun swiftc -target "${arch}-apple-macosx13.0" \
  macos/CameraShared/VirtualCameraContract.swift \
  macos/Runner/VirtualCamera/VirtualCameraRustSession.swift \
  macos/Runner/VirtualCamera/VirtualCameraFrameFormatter.swift \
  macos/Runner/VirtualCamera/VirtualCameraSink.swift \
  macos/Runner/VirtualCamera/VirtualCameraCoordinator.swift \
  test/native/virtual_camera_host_test.swift \
  -o "$work_dir/host-tests"
"$work_dir/host-tests"
xcrun swiftc -target "${arch}-apple-macosx13.0" \
  macos/CameraShared/VirtualCameraContract.swift \
  macos/AnyDeckCameraExtension/CameraFrameStore.swift \
  test/native/virtual_camera_extension_test.swift \
  -o "$work_dir/extension-tests"
"$work_dir/extension-tests"
