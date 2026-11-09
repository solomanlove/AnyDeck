import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../../app/settings/app_settings_controller.dart';

import '../providers/app_providers.dart';
import '../providers/host_network_provider.dart';
import '../network/host_network_info.dart';
import '../adb/discovered_device.dart';
import 'device_share_auto_prepare.dart';
import 'device_share_discovery.dart';
import 'device_share_network_watch.dart';
import 'device_share_service.dart';
import 'device_share_store.dart';

/// 主窗口常驻资源归属，页面关闭不终止共享，应用退出统一回收。
final deviceShareServiceProvider = Provider<DeviceShareService>((ref) {
  final isSub = ref.read(windowIdProvider).isNotEmpty;
  final service = DeviceShareService(
    ref.watch(adbServiceProvider),
    store: isSub ? MemoryDeviceShareStore() : FileDeviceShareStore(),
    discovery: isSub ? null : UdpDeviceShareDiscovery(),
  );
  if (isSub) {
    ref.onDispose(() => unawaited(service.dispose()));
    return service;
  }
  var network = const HostNetworkInfo();
  List<DiscoveredDevice> devices =
      ref.read(discoveredDevicesProvider).value ?? [];
  Map<String, String> serials = {};
  StreamSubscription<HostNetworkInfo>? networkSubscription;
  bool disposed = false;
  void observe() {
    if (!disposed) {
      service.updateEnvironment(
        DeviceShareEnvironment(
          network: network,
          devices: devices,
          serials: serials,
        ),
      );
    }
  }

  void syncNetworkWatch() {
    if (disposed) return;
    if (service.hasAutomaticShares && networkSubscription == null) {
      networkSubscription =
          DeviceShareNetworkWatch(
            ref.read(hostNetworkServiceProvider),
          ).watch().listen((value) {
            network = value;
            observe();
          });
    } else if (!service.hasAutomaticShares && networkSubscription != null) {
      unawaited(networkSubscription!.cancel());
      networkSubscription = null;
    }
  }

  final changes = service.changes.listen((_) => syncNetworkWatch());
  final lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      await service.dispose();
      return AppExitResponse.exit;
    },
  );
  ref.listen(discoveredDevicesProvider, (_, next) {
    if (next case AsyncData(:final value)) {
      devices = value;
      observe();
    }
  });
  ref.listen(deviceRegistryProvider, (_, next) {
    serials = {
      for (final device in next)
        if (device.serial != null)
          for (final id in {device.id, ...device.connections})
            id: device.serial!,
    };
    observe();
  });
  unawaited(service.initialize().catchError((Object _, StackTrace _) {}));
  ref.onDispose(() {
    disposed = true;
    lifecycle.dispose();
    unawaited(changes.cancel());
    unawaited(networkSubscription?.cancel() ?? Future<void>.value());
    unawaited(service.dispose());
  });
  return service;
});

/// 只在会话状态变化时触发重绘，视频和文件数据不经过 Provider。
final deviceShareChangesProvider = StreamProvider<int>((ref) {
  return ref.watch(deviceShareServiceProvider).changes;
});
