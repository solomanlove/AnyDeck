import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/ios/ios_mirror_service.dart';

/// 按设备保存用户主动获取的静态截图；不启动投屏或周期截图。
final deviceScreenPreviewProvider = AsyncNotifierProvider.autoDispose
    .family<DeviceScreenPreviewController, Uint8List?, String>(
      DeviceScreenPreviewController.new,
    );

class DeviceScreenPreviewController extends AsyncNotifier<Uint8List?> {
  DeviceScreenPreviewController(this.deviceId);

  final String deviceId;
  KeepAliveLink? _retained;
  Timer? _releaseTimer;

  @override
  Uint8List? build() {
    ref.onDispose(() => _releaseTimer?.cancel());
    return null;
  }

  /// 只对当前仍在线的注册设备取图，复用各平台现有的有界截图命令。
  Future<void> capture() async {
    if (state.isLoading) return;
    final device = ref
        .read(deviceRegistryProvider)
        .where((device) => device.id == deviceId && device.isOnline)
        .firstOrNull;
    if (device == null) return;
    // 视图切换不会中断取图；短暂保留最近封面，空闲一分钟后释放原始字节。
    _releaseTimer?.cancel();
    _retained ??= ref.keepAlive();
    state = const AsyncLoading();
    try {
      final bytes = device.isIos
          ? await ref
                .read(iosCommandServiceProvider)
                .captureScreenshot(device.id)
          : device.isHarmony
          ? await ref.read(hdcServiceProvider).captureScreenshot(device.id)
          : await ref.read(adbServiceProvider).captureScreenshot(device.id);
      if (ref.mounted) state = AsyncData(bytes);
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
    } finally {
      if (ref.mounted) {
        _releaseTimer = Timer(const Duration(minutes: 1), () {
          _retained?.close();
          _retained = null;
        });
      }
    }
  }
}
