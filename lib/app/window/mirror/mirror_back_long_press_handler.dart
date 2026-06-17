import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device_actions/foreground_app_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../widget/app_toast.dart';

/// 处理投屏工具栏返回键长按：先提示前台应用，持续按住则强停非桌面应用。
class MirrorBackLongPressHandler {
  MirrorBackLongPressHandler({required this.ref, required this.deviceId});

  final WidgetRef ref;
  final String deviceId;

  Timer? _previewTimer;
  Timer? _forceStopTimer;
  ForegroundAppInfo? _targetInfo;
  bool _pointerDown = false;
  bool _longPressTriggered = false;

  bool get shouldSuppressBack => _longPressTriggered;

  void handlePointerDown(BuildContext context) {
    cancel();
    _pointerDown = true;
    _longPressTriggered = false;
    _previewTimer = Timer(const Duration(milliseconds: 450), () {
      _previewTarget(context);
    });
    _forceStopTimer = Timer(const Duration(milliseconds: 1200), () {
      _forceStopTarget(context);
    });
  }

  void handlePointerUp() {
    _pointerDown = false;
    _previewTimer?.cancel();
    _forceStopTimer?.cancel();
  }

  void cancel() {
    _pointerDown = false;
    _previewTimer?.cancel();
    _forceStopTimer?.cancel();
    _previewTimer = null;
    _forceStopTimer = null;
    _targetInfo = null;
  }

  Future<void> _previewTarget(BuildContext context) async {
    if (!_pointerDown) {
      return;
    }
    _longPressTriggered = true;
    try {
      final info = await ref
          .read(foregroundAppServiceProvider)
          .foregroundApp(deviceId);
      _targetInfo = info;
      if (!context.mounted || !_pointerDown) {
        return;
      }
      _showFloatingMessage(
        context,
        info.isHome ? '桌面' : '当前应用：${info.displayName}',
      );
    } catch (e) {
      if (context.mounted && _pointerDown) {
        _showFloatingMessage(context, '获取当前应用失败: $e', isError: true);
      }
    }
  }

  Future<void> _forceStopTarget(BuildContext context) async {
    if (!_pointerDown) {
      return;
    }
    try {
      final service = ref.read(foregroundAppServiceProvider);
      final info = _targetInfo ?? await service.foregroundApp(deviceId);
      _targetInfo = info;
      if (!context.mounted || !_pointerDown) {
        return;
      }
      if (info.isHome || info.packageName.isEmpty) {
        _showFloatingMessage(context, '桌面');
        return;
      }

      final result = await service.forceStopPackage(deviceId, info.packageName);
      if (!context.mounted || !_pointerDown) {
        return;
      }
      _showFloatingMessage(
        context,
        result.isSuccess ? '已强停：${info.displayName}' : '强停失败：${result.message}',
        isError: !result.isSuccess,
      );
    } catch (e) {
      if (context.mounted && _pointerDown) {
        _showFloatingMessage(context, '强停失败: $e', isError: true);
      }
    }
  }

  void _showFloatingMessage(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    AppToast.show(context, message, isError: isError);
  }
}
