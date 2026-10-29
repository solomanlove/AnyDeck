import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/scrcpy/mirror_transport_resolver.dart';
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
    super.dispose();
  }

  /// 同一轮恢复只尝试每条连接一次，成功持续运行后允许下一轮重新选路。
  Future<void> _recover(String failedId) async {
    if (_recovering || failedId != _deviceId || !mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final currentId = _deviceId;
    ref.listen(mirrorDisconnectedProvider(currentId), (previous, next) {
      if (previous != next) unawaited(_recover(currentId));
    });
    ref.listen(activeEmbeddedMirrorProvider(currentId), (previous, next) {
      if (next != null) _connectedAt = DateTime.now();
    });
    return Stack(
      fit: StackFit.expand,
      children: [
        KeyedSubtree(
          key: ValueKey(currentId),
          child: widget.builder(context, currentId),
        ),
        if (_recovering)
          ColoredBox(
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
