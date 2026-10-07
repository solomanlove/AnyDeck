import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/log_service.dart';
import '../logging/app_log_recorder.dart';
import 'ios_command_service.dart';
import 'ios_device_service.dart';
import 'ios_control_gateway.dart';

/// Riverpod Provider definitions for iOS Services
final iosDeviceServiceProvider = Provider<IosDeviceService>((ref) {
  // 订阅全局日志历史记录，以便 go-ios 的输出能被捕获
  final service = IosDeviceService(
    onLog: (message, {tag = 'ios', level = 'I'}) {
      ref
          .read(logHistoryProvider.notifier)
          .log(message, tag: tag, level: level);
    },
  );
  ref.onDispose(service.stopAll);
  return service;
});

/// iOS 应用、文件、日志、进程、截图与自动化命令入口。
final iosCommandServiceProvider = Provider<IosCommandService>((ref) {
  return IosCommandService(
    onLog: (message, {tag = 'ios', level = 'I'}) {
      ref
          .read(logHistoryProvider.notifier)
          .log(message, tag: tag, level: level);
    },
  );
});

/// 原生采集尺寸与诊断数据，低频更新，不携带像素。
class IosUsbFrameNotifier extends Notifier<Map<String, dynamic>> {
  IosUsbFrameNotifier(this.udid);
  final String udid;
  @override
  Map<String, dynamic> build() => {};
  void update(Map<String, dynamic> value) => state = value;
}

final iosUsbFrameProvider =
    NotifierProvider.family<IosUsbFrameNotifier, Map<String, dynamic>, String>(
      IosUsbFrameNotifier.new,
    );

/// 保留 int? 会话接口以兼容窗口在线判断，值现在是本引擎的 Texture ID。
class ActiveIosMirrorNotifier extends Notifier<int?> {
  ActiveIosMirrorNotifier(this.udid);
  final String udid;
  Timer? _poll;
  bool _reading = false;
  bool _changing = false;
  int _generation = 0;

  @override
  int? build() {
    final service = ref.read(iosDeviceServiceProvider);
    ref.onDispose(() {
      _generation++;
      _poll?.cancel();
      unawaited(service.stopMirroring(udid));
    });
    return service.getPort(udid);
  }

  Future<void> toggleMirroring() async {
    if (_changing) return;
    if (state != null) {
      await forceStop();
      return;
    }
    _changing = true;
    final generation = ++_generation;
    final service = ref.read(iosDeviceServiceProvider);
    ref.read(iosUsbFrameProvider(udid).notifier).update({});
    try {
      final texture = await service.startMirroring(udid: udid);
      if (!ref.mounted || generation != _generation) return;
      state = texture;
      await _readStatus();
      if (state != null) {
        _poll = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => _readStatus(),
        );
      }
    } finally {
      _changing = false;
    }
  }

  Future<void> _readStatus() async {
    if (_reading || !ref.mounted || state == null) return;
    _reading = true;
    final generation = _generation;
    try {
      final status = await ref
          .read(iosDeviceServiceProvider)
          .usbMirror
          .status(udid);
      if (!ref.mounted || generation != _generation) return;
      ref.read(iosUsbFrameProvider(udid).notifier).update(status);
      if (status.isEmpty ||
          status['closed'] == true ||
          '${status['error'] ?? ''}'.isNotEmpty ||
          ((status['frameAgeMs'] as num?) ?? 0) > 10000) {
        AppLogRecorder.instance.record(
          'USB capture ended: $status',
          tag: 'ios-video',
          level: 'E',
        );
        await forceStop();
      }
    } catch (_) {
      if (ref.mounted && generation == _generation) await forceStop();
    } finally {
      _reading = false;
    }
  }

  Future<void> forceStop() async {
    ++_generation;
    _poll?.cancel();
    _poll = null;
    state = null;
    await ref.read(iosDeviceServiceProvider).stopMirroring(udid);
    // 关闭该设备投屏时结束共享控制；只终止自身持有的 Runner/forward。
    try {
      await IosControlGateway.call(udid, 'stop');
    } catch (_) {}
  }
}

final activeIosMirrorProvider =
    NotifierProvider.family<ActiveIosMirrorNotifier, int?, String>(
      ActiveIosMirrorNotifier.new,
    );
