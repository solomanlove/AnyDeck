import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../providers/app_providers.dart';
import 'device_share_service.dart';

/// 主窗口常驻资源归属，页面关闭不终止共享，应用退出统一回收。
final deviceShareServiceProvider = Provider<DeviceShareService>((ref) {
  final service = DeviceShareService(ref.watch(adbServiceProvider));
  final lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      await service.dispose();
      return AppExitResponse.exit;
    },
  );
  ref.listen(discoveredDevicesProvider, (_, next) {
    if (next case AsyncData(:final value)) service.validateHosts(value);
  });
  ref.onDispose(() {
    lifecycle.dispose();
    unawaited(service.dispose());
  });
  return service;
});

/// 只在会话状态变化时触发重绘，视频和文件数据不经过 Provider。
final deviceShareChangesProvider = StreamProvider<int>((ref) {
  return ref.watch(deviceShareServiceProvider).changes;
});
