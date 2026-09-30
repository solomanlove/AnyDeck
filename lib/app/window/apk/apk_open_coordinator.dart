import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/apk/apk_install_queue.dart';
import '../../../core/apk/apk_file_open_queue.dart';
import '../../../core/providers/app_providers.dart';
import '../../router/app_router.dart';
import '../../router/dashboard_route.dart';
import '../desktop_window_manager_service.dart';
import '../multi_window_compat.dart';
import '../sub_window_method_dispatcher.dart';

/// 主引擎负责文件事件和安装任务；子窗口关闭不影响已提交的安装。
class ApkOpenCoordinator {
  ApkOpenCoordinator(this.container);
  final ProviderContainer container;
  static const _channel = MethodChannel('any_deck/apk_files');
  final _installs = ApkInstallQueue();
  late final ApkFileOpenQueue _opens;
  late String _mainWindowId;
  final _uiReady = Completer<void>();
  Future<Map<String, dynamic>>? _deviceRead;
  DateTime _deviceReadAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> initialize() async {
    _mainWindowId = (await WindowController.fromCurrentEngine()).windowId;
    _opens = ApkFileOpenQueue(
      ready: _uiReady.future,
      openDocument: _open,
      onError: (error) => debugPrint('APK window: $error'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _uiReady.complete());
    SubWindowMethodDispatcher.registerHandler(handleWindowCall);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFiles') _opens.add(call.arguments);
    });
    _opens.add(await _channel.invokeMethod<List<dynamic>>('ready'));
  }

  Future<void> _open(String path) async {
    await createAdbManageWindow(
      arguments: {
        'type': 'apk_details',
        'path': path,
        'mainWindowId': _mainWindowId,
      },
      frame: const Rect.fromLTWH(100, 100, 1120, 780),
      title: 'AnyDeck · ${Uri.file(path).pathSegments.last}',
    );
  }

  // 多个 APK 窗口共享短期设备快照，安装前仍重新确认实际连接。
  Future<Map<String, dynamic>> _deviceSnapshot() {
    final now = DateTime.now();
    if (_deviceRead != null && now.difference(_deviceReadAt).inSeconds < 2) {
      return _deviceRead!;
    }
    _deviceReadAt = now;
    return _deviceRead = _devices();
  }

  Future<Map<String, dynamic>> _devices() async {
    final devices = [...await container.read(adbServiceProvider).listDevices()];
    final registry = container.read(deviceRegistryProvider);
    final seen = <String>{};
    final rows = <Map<String, dynamic>>[];
    // 在线连接优先；复用 registry 的物理设备身份，保留实际通信 serial。
    devices.sort((a, b) {
      final online = (b.isOnline ? 1 : 0).compareTo(a.isOnline ? 1 : 0);
      return online == 0 ? a.id.compareTo(b.id) : online;
    });
    for (final device in devices) {
      final known = registry
          .where((r) => r.id == device.id || r.connections.contains(device.id))
          .firstOrNull;
      if (known?.isIos == true || known?.isHarmony == true) continue;
      if (!seen.add(known?.serial ?? device.id)) continue;
      rows.add({
        'id': device.id,
        'name': known?.displayName ?? device.displayName,
        'online': device.isOnline,
        'status': device.status,
      });
    }
    final selected = container.read(selectedDeviceProvider)?.id;
    final preferred =
        rows.where((r) => r['id'] == selected).firstOrNull?['id'] ??
        rows
            .where(
              (r) => registry.any(
                (known) =>
                    (known.id == selected ||
                        known.connections.contains(selected)) &&
                    (known.id == r['id'] ||
                        known.connections.contains(r['id'])),
              ),
            )
            .firstOrNull?['id'];
    return {'devices': rows, 'preferred': preferred};
  }

  Future<void> _refreshPackage(String serial, String packageName) async {
    if (container.read(packagesProvider(serial)).hasError) {
      container.invalidate(packagesProvider(serial));
    }
    final ready = Completer<void>();
    final subscription = container.listen(packagesProvider(serial), (_, next) {
      if (!next.isLoading && !ready.isCompleted) ready.complete();
    }, fireImmediately: true);
    try {
      await ready.future.timeout(const Duration(seconds: 30));
      final state = container.read(packagesProvider(serial));
      if (state.hasError) throw state.error!;
      await container
          .read(packagesProvider(serial).notifier)
          .refreshSinglePackage(packageName);
      if (!container
          .read(packagesProvider(serial))
          .requireValue
          .any((p) => p.name == packageName)) {
        throw const FormatException('apkDeviceUnavailable');
      }
    } finally {
      subscription.close();
    }
  }

  /// 分发器统一调用；公开入口便于测试 serial、队列和缓存刷新链路。
  Future<dynamic> handleWindowCall(MethodCall call) async {
    if (!call.method.startsWith('apk_')) return null;
    try {
      if (call.method == 'apk_devices') return await _deviceSnapshot();
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final serial = args['serial'] as String;
      final packageName = args['packageName'] as String;
      if (call.method == 'apk_install') {
        return await _installs.run(
          serial,
          args['requestId'] as String,
          () async {
            final snapshot = await _devices();
            final online = (snapshot['devices'] as List).any(
              (d) => d['id'] == serial && d['online'] == true,
            );
            if (!online) {
              return {'success': false, 'error': 'apkDeviceUnavailable'};
            }
            final file = File(args['path'] as String);
            final stat = await file.stat();
            if (!file.path.toLowerCase().endsWith('.apk') ||
                stat.type != FileSystemEntityType.file ||
                stat.size != args['size'] ||
                stat.modified.microsecondsSinceEpoch != args['modified']) {
              return {'success': false, 'error': 'apkFileChanged'};
            }
            final result = await container
                .read(appManagementServiceProvider)
                .installApk(serial, file.path);
            if (!result.isSuccess) {
              return {'success': false, 'error': result.message};
            }
            String? warning;
            try {
              await _refreshPackage(serial, packageName);
            } catch (error) {
              warning = error.toString();
            }
            return {
              'success': true,
              'serial': serial,
              'packageName': packageName,
              'warning': warning,
            };
          },
        );
      }
      if (call.method == 'apk_show_installed') {
        final devices = [
          ...await container.read(adbServiceProvider).listDevices(),
        ];
        final device = devices
            .where((d) => d.id == serial && d.isOnline)
            .firstOrNull;
        if (device == null) {
          return {'success': false, 'error': 'apkDeviceUnavailable'};
        }
        await _refreshPackage(serial, packageName);
        container.read(userClearedDeviceSelectionProvider.notifier).state =
            false;
        container.read(selectedDeviceProvider.notifier).select(device);
        container.read(selectedToolTabProvider.notifier).select(2);
        container.read(selectedAppPackageProvider.notifier).state = packageName;
        container
            .read(appRouterProvider)
            .goNamed(
              AppRouteNames.appDetails,
              pathParameters: {
                'deviceId': device.id,
                'packageName': packageName,
              },
            );
        await DesktopWindowManagerService.showWindow();
        return {'success': true};
      }
      return {'success': false, 'error': 'apkInvalidRequest'};
    } catch (error) {
      return {
        'success': false,
        'devices': <dynamic>[],
        'error': error.toString(),
      };
    }
  }
}
