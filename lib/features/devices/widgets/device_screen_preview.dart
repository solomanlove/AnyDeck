import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../controller/device_screen_preview_controller.dart';

/// 为设备墙可见卡片拥有一次静态截图；不创建实时投屏或周期定时器。
///
/// [deviceId] 对应真实注册设备，[online] 为当前在线状态；[builder] 只负责展示
/// 截图快照。卡片卸载、切换列表或主窗口隐藏设备页时撤回未执行请求；再次可见会更新。
class DeviceScreenPreview extends ConsumerStatefulWidget {
  const DeviceScreenPreview({
    super.key,
    required this.deviceId,
    required this.online,
    required this.builder,
  });
  final String deviceId;
  final bool online;
  final Widget Function(BuildContext, AsyncValue<Uint8List?>) builder;

  @override
  ConsumerState<DeviceScreenPreview> createState() =>
      _DeviceScreenPreviewState();
}

class _DeviceScreenPreviewState extends ConsumerState<DeviceScreenPreview> {
  DeviceScreenPreviewController? _controller;
  ProviderSubscription<int>? _pageSubscription;
  var _pageVisible = false;
  var _syncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _pageVisible = ref.read(selectedToolTabProvider) == -1;
    _pageSubscription = ref.listenManual(selectedToolTabProvider, (_, next) {
      _pageVisible = next == -1;
      _syncVisibility();
    });
    _syncVisibility();
  }

  @override
  void didUpdateWidget(covariant DeviceScreenPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      _controller?.setVisible(false);
      _controller = null;
    }
    if (oldWidget.deviceId != widget.deviceId ||
        oldWidget.online != widget.online) {
      _syncVisibility();
    }
  }

  void _syncVisibility() {
    final generation = ++_syncGeneration;
    if (!_pageVisible ||
        !widget.online ||
        widget.deviceId.startsWith('airplay-')) {
      _controller?.setVisible(false);
      return;
    }
    // 首帧后再发布 Loading，避免在 Flutter build 生命周期内修改 Provider。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _syncGeneration) return;
      _controller ??= ref.read(
        deviceScreenPreviewProvider(widget.deviceId).notifier,
      );
      _controller!.setVisible(true);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    ref.watch(deviceScreenPreviewProvider(widget.deviceId)),
  );

  @override
  void dispose() {
    _syncGeneration++;
    _controller?.setVisible(false);
    _pageSubscription?.close();
    super.dispose();
  }
}
