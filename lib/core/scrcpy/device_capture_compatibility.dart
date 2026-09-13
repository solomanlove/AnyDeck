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
