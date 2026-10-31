import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/adb/discovered_device.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/scrcpy/mirror_transport_resolver.dart';
import '../../../core/scrcpy/mirror_transport_type.dart';
import '../../../core/scrcpy/mirror_transport_devices_provider.dart';
import '../../l10n/app_localizations.dart';

/// 在同一原生窗口内切换 Android 投屏连接，统一重绑画面、控制与截图。
/// [builder] 使用当前在线 transport 创建内容；[deviceId] 是启动时的连接。
class AndroidMirrorTransportHost extends ConsumerStatefulWidget {
  const AndroidMirrorTransportHost({
    super.key,
    required this.deviceId,
    required this.builder,
  });

  final String deviceId;
  final Widget Function(BuildContext context, String deviceId) builder;

  @override
  ConsumerState<AndroidMirrorTransportHost> createState() =>
      _AndroidMirrorTransportHostState();
}

class _AndroidMirrorTransportHostState
    extends ConsumerState<AndroidMirrorTransportHost> {
  late final MirrorTransportResolver _resolver;
  late String _deviceId;
  final _failedRoutes = <String>{};
  bool _recovering = false;
  DateTime? _connectedAt;
  List<DiscoveredDevice> _devices = const [];
  Timer? _selectionTimer;
  bool _checkingPreferred = false;
  bool _preferredCheckPending = false;
  int _devicesRevision = 0;
  int _routeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _deviceId = widget.deviceId;
    _resolver = MirrorTransportResolver(
      ref.read(adbServiceProvider),
      _deviceId,
    );
  }

  @override
  void dispose() {
    _resolver.dispose();
    _selectionTimer?.cancel();
    super.dispose();
  }

  /// 同一轮恢复只尝试每条连接一次，成功持续运行后允许下一轮重新选路。
  Future<void> _recover(String failedId) async {
    if (_recovering || failedId != _deviceId || !mounted) return;
    ++_routeGeneration;
    setState(() => _recovering = true);
    if (_connectedAt != null &&
        DateTime.now().difference(_connectedAt!) >=
            const Duration(seconds: 3)) {
      _failedRoutes.clear();
    }
    _connectedAt = null;
    _failedRoutes.add(failedId);
    try {
      final next = await _resolver.resolve(excluded: _failedRoutes);
      if (!mounted || next == null) return;
      // 完成旧会话清理后再重建内容，所有操作均使用新 ID，不保留失效的 USB 路由。
      await ref
          .read(activeEmbeddedMirrorProvider(failedId).notifier)
          .forceStop();
      if (!mounted) return;
      setState(() => _deviceId = next);
    } catch (error) {
      debugPrint('Mirror transport recovery failed: $error');
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  /// 连接事件只做短防抖；正常投屏时不轮询列表，也不因同级通道变化重建会话。
  void _schedulePreferredCheck() {
    _selectionTimer?.cancel();
    if (_checkingPreferred) {
      _preferredCheckPending = true;
      return;
    }
    if (_recovering ||
        MirrorTransportType.fromDeviceId(_deviceId) == MirrorTransportType.usb) {
      return;
    }
    _selectionTimer = Timer(const Duration(milliseconds: 350), _checkPreferred);
  }

  Future<void> _checkPreferred() async {
    if (!mounted ||
        _recovering ||
        _checkingPreferred ||
        ref.read(activeEmbeddedMirrorProvider(_deviceId)) == null) {
      return;
    }
    _checkingPreferred = true;
    final currentId = _deviceId;
    final generation = _routeGeneration;
    final revision = _devicesRevision;
    var switching = false;
    try {
      final next = await _resolver.resolve(
        excluded: _failedRoutes,
        devices: _devices,
        betterThan: currentId,
      );
      if (!mounted ||
          generation != _routeGeneration ||
          _recovering ||
          revision != _devicesRevision ||
          next == null ||
          ref.read(activeEmbeddedMirrorProvider(currentId)) == null) {
        return;
      }
      // 旧通道仍可用时只向更高优先级迁移；新通道失败后可回退到原健康连接。
      ++_routeGeneration;
      switching = true;
      setState(() => _recovering = true);
      _connectedAt = null;
      await ref
          .read(activeEmbeddedMirrorProvider(currentId).notifier)
          .forceStop();
      if (mounted) setState(() => _deviceId = next);
    } catch (error) {
      debugPrint('Mirror preferred transport check failed: $error');
    } finally {
      _checkingPreferred = false;
      if (mounted) {
        if (switching) setState(() => _recovering = false);
        final recheck = _preferredCheckPending || revision != _devicesRevision;
        _preferredCheckPending = false;
        if (recheck) _schedulePreferredCheck();
      }
    }
  }

  void _onDevicesChanged(List<DiscoveredDevice> devices) {
    final previouslyOnline = _devices
        .where((d) => d.isOnline)
        .map((d) => d.id)
        .toSet();
    final online = devices.where((d) => d.isOnline).map((d) => d.id).toSet();
    // 只有真实的重新上线才能解除本轮失败限制，避免坏 USB 在无线恢复后反复抢占。
    _failedRoutes.removeAll(online.difference(previouslyOnline));
    _devices = devices;
    ++_devicesRevision;
    if (previouslyOnline.contains(_deviceId) &&
        !online.contains(_deviceId) &&
        ref.read(activeEmbeddedMirrorProvider(_deviceId)) != null) {
      unawaited(_recover(_deviceId));
    } else {
      _schedulePreferredCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(mirrorTransportDevicesProvider, (previous, next) {
      if (next.hasValue) _onDevicesChanged(next.requireValue);
    });
    final currentId = _deviceId;
    ref.listen(mirrorDisconnectedProvider(currentId), (previous, next) {
      if (previous != next) unawaited(_recover(currentId));
    });
    ref.listen(activeEmbeddedMirrorProvider(currentId), (previous, next) {
      if (next != null) {
        _connectedAt = DateTime.now();
        _schedulePreferredCheck();
      } else {
        _selectionTimer?.cancel();
      }
    });
    return Stack(
      fit: StackFit.expand,
      children: [
        KeyedSubtree(
          key: ValueKey(currentId),
          child: widget.builder(context, currentId),
        ),
        if (_recovering)
          // 遮罩与内容 Scaffold 同级，须独立提供 Material 默认文字样式。
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(context.l10n.t('startingMirrorService')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
