import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../harmony/hdc_service.dart';
import 'device_tracking_providers.dart';
import 'service_providers.dart';

/// 在线鸿蒙设备的 WLAN 地址快照；独立于静态元数据缓存低频刷新。
final harmonyDeviceIpsProvider =
    StreamProvider.autoDispose<Map<String, String>>((ref) {
      if (ref.watch(windowIdProvider).isNotEmpty) return Stream.value(const {});
      // 设备发现会重复发布相同列表，仅在线目标变化时重建探测任务。
      final targets = ref.watch(
        discoveredDevicesProvider.select((value) {
          final ids = value.value
              ?.where((device) => device.isHarmony && device.isOnline)
              .map((device) => device.id)
              .toSet()
              .toList();
          ids?.sort();
          return ids?.join('\n') ?? '';
        }),
      );
      if (targets.isEmpty) return Stream.value(const {});

      final hdc = ref.watch(hdcServiceProvider);
      final controller = StreamController<Map<String, String>>();
      final ips = <String, String>{};
      var disposed = false;
      var running = false;

      Future<void> refresh() async {
        if (disposed || running) return;
        running = true;
        try {
          for (final id in targets.split('\n')) {
            if (disposed) return;
            try {
              final result = await hdc.shell(
                id,
                'ifconfig wlan0',
                timeout: const Duration(seconds: 3),
              );
              if (disposed) return;
              // 命令失败保留历史值；成功但没有地址则明确清除旧 WLAN IP。
              if (!result.isSuccess) continue;
              final ip = HdcService.parseIpFromIfconfig(result.stdout) ?? '-';
              if (ips[id] == ip) continue;
              ips[id] = ip;
              controller.add(Map.unmodifiable(ips));
            } catch (_) {
              // 临时断线不终止整个监控，下一个周期重试。
            }
          }
        } finally {
          running = false;
        }
      }

      final timer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => refresh(),
      );
      ref.onDispose(() {
        disposed = true;
        timer.cancel();
        unawaited(controller.close());
      });
      unawaited(refresh());
      return controller.stream;
    });
