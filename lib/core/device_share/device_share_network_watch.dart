import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../network/host_network_info.dart';
import '../network/host_network_service.dart';

/// 按需订阅网络事件；低频校验弥补同一网卡/同一 IP 切换 SSID 的系统事件缺口。
/// 自动规则全部暂停后由主窗口立即取消，避免常驻扫描或 CLI 轮询。
class DeviceShareNetworkWatch {
  DeviceShareNetworkWatch(
    this.service, {
    this.interval = const Duration(seconds: 5),
  });
  final HostNetworkService service;
  final Duration interval;
  static const _events = EventChannel('any_deck/host_network/events');

  Stream<HostNetworkInfo> watch() {
    late StreamController<HostNetworkInfo> controller;
    StreamSubscription<dynamic>? subscription;
    Timer? timer, debounce;
    bool closed = false, reading = false, again = false;
    Future<void> read() async {
      if (closed) return;
      if (reading) {
        again = true;
        return;
      }
      reading = true;
      try {
        final network = await service.readForSharing();
        if (!closed) controller.add(network);
      } catch (_) {
        if (!closed) controller.add(const HostNetworkInfo());
      } finally {
        reading = false;
        if (again && !closed) {
          again = false;
          unawaited(read());
        }
      }
    }

    controller = StreamController<HostNetworkInfo>(
      onListen: () {
        unawaited(read());
        timer = Timer.periodic(interval, (_) => unawaited(read()));
        if (Platform.isMacOS) {
          subscription = _events.receiveBroadcastStream().listen((_) {
            debounce?.cancel();
            debounce = Timer(
              const Duration(milliseconds: 150),
              () => unawaited(read()),
            );
          }, onError: (_) {});
        }
      },
      onCancel: () async {
        closed = true;
        timer?.cancel();
        debounce?.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
