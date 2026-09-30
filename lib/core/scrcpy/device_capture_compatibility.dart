import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

/// 复用全局设备版本元数据；未知版本不猜测为支持。
final captureSdkProvider = FutureProvider.autoDispose.family<int?, String>((
  ref,
  deviceId,
) async {
  // 版本由全局设备 Registry 提供；实际启动时 Rust 再读取 SDK 校验。
  return ref.watch(deviceSdkVersionProvider(deviceId));
});

/// 本轮 Rust 库、PCM 播放与 Texture 打包目前仅提供 macOS 入口。
final captureHostSupportedProvider = Provider<bool>((ref) => Platform.isMacOS);

/// 检测设备是否支持前后摄像头同时并发开启（Concurrent Camera Streaming）。
/// 判定依据：
/// 1. 宿主必须支持视频解码（macOS）；
/// 2. Android 11 (API 30)+ 引入并发摄像头，本页面 scrcpy camera 需 Android 12 (API 31)+；
/// 3. 设备需具备 android.hardware.camera.concurrent 系统特性（通过 pm has-feature 校验）。
final concurrentCameraSupportedProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, deviceId) async {
      final hostSupported = ref.watch(captureHostSupportedProvider);
      if (!hostSupported) return false;
      final online = ref.watch(deviceOnlineProvider(deviceId));
      if (!online) return false;
      final sdk = await ref.watch(captureSdkProvider(deviceId).future);
      if (sdk == null || sdk < 31) return false;
      final adb = ref.watch(adbServiceProvider);
      try {
        final result = await adb.shell(
          deviceId,
          'pm has-feature android.hardware.camera.concurrent',
          timeout: const Duration(seconds: 4),
        );
        return result.stdout.trim().toLowerCase() == 'true';
      } catch (_) {
        return false;
      }
    });
