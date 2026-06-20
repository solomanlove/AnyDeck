import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/log_service.dart';
import 'ios_device_service.dart';

/// Riverpod Provider definitions for iOS Services
final iosDeviceServiceProvider = Provider<IosDeviceService>((ref) {
  // 订阅全局日志历史记录，以便 go-ios 的输出能被捕获
  final service = IosDeviceService(
    onLog: (message, {tag = 'ios', level = 'I'}) {
      ref.read(logHistoryProvider.notifier).log(message, tag: tag, level: level);
    },
  );
  ref.onDispose(service.stopAll);
  return service;
});

class ActiveIosMirrorNotifier extends Notifier<int?> {
  ActiveIosMirrorNotifier(this.udid);

  final String udid;

  @override
  int? build() {
    ref.keepAlive();
    
    final service = ref.watch(iosDeviceServiceProvider);
    final port = service.getPort(udid);
    if (port != null) {
      Future.microtask(() => _listenToProcessExit(port));
    }
    return port;
  }

  Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  void _listenToProcessExit(int port) {
    final service = ref.read(iosDeviceServiceProvider);
    final process = service.getStreamProcess(udid);
    process?.exitCode.then((code) {
      if (state == port) {
        service.stopMirroring(udid);
        state = null;
      }
    });
  }

  Future<void> toggleMirroring() async {
    final service = ref.read(iosDeviceServiceProvider);
    if (service.isActive(udid)) {
      await service.stopMirroring(udid);
      state = null;
    } else {
      try {
        final port = await _findFreePort();
        final activePort = await service.startMirroring(udid: udid, port: port);
        state = activePort;
        _listenToProcessExit(activePort);
      } catch (e) {
        state = null;
        rethrow;
      }
    }
  }

  Future<void> forceStop() async {
    final service = ref.read(iosDeviceServiceProvider);
    if (service.isActive(udid)) {
      await service.stopMirroring(udid);
      state = null;
    }
  }
}

final activeIosMirrorProvider =
    NotifierProvider.family<ActiveIosMirrorNotifier, int?, String>(
      ActiveIosMirrorNotifier.new,
    );
