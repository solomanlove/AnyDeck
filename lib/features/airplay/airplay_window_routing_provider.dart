import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/airplay/airplay_mirror_window_coordinator.dart';
import '../../core/airplay/airplay_server_service.dart';
import '../../core/providers/app_providers.dart';
import 'airplay_mirror_target.dart';

/// 主 Isolate 持有窗口路由，页面切换或重建不会丢失已经建立的镜像连接。
/// 视频投放由 AirPlayVideoPlayer 独立路由到原生播放器，不复用手机窗口。
final airplayWindowRoutingProvider = Provider<void>((ref) {
  final coordinator = AirPlayMirrorWindowCoordinator(
    open: (session) async {
      final merged = mergeAirPlayDevicesIntoList(
        ref.read(deviceRegistryProvider),
        ref.read(airplaySessionProvider),
      );
      final id = merged.sessionByDeviceId.entries
          .where((entry) => entry.value.id == session.id)
          .map((entry) => entry.key)
          .firstOrNull;
      final device = merged.devices
          .where((device) => device.id == id)
          .firstOrNull;
      return openAirPlayMirrorWindow(
        session,
        deviceId: device?.id,
        deviceName: device?.displayName,
      );
    },
  );
  void reconcile() =>
      coordinator.reconcile(ref.read(airplaySessionProvider), DateTime.now());
  ref.listen(
    airplaySessionProvider,
    (_, next) => reconcile(),
    fireImmediately: true,
  );
  // 状态未变化也可重试失败开窗；成功后不再产生跨窗口消息。
  final timer = Timer.periodic(const Duration(seconds: 1), (_) => reconcile());
  ref.onDispose(() {
    timer.cancel();
    coordinator.clear();
  });
});
