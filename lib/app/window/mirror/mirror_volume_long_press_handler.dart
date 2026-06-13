import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';

/// 处理投屏工具栏音量键长按逻辑：
/// 长按音量+：音量变成最大
/// 长按音量-：音量变成静音
class MirrorVolumeLongPressHandler {
  MirrorVolumeLongPressHandler({
    required this.ref,
    required this.deviceId,
  });

  final WidgetRef ref;
  final String deviceId;

  Timer? _volumeUpTimer;
  Timer? _volumeDownTimer;
  bool _volumeUpPointerDown = false;
  bool _volumeDownPointerDown = false;
  bool _volumeUpLongPressTriggered = false;
  bool _volumeDownLongPressTriggered = false;

  bool get shouldSuppressVolumeUp => _volumeUpLongPressTriggered;
  bool get shouldSuppressVolumeDown => _volumeDownLongPressTriggered;

  /// 处理音量+按下
  void handleVolumeUpPointerDown(BuildContext context) {
    _cancelVolumeUp();
    _volumeUpPointerDown = true;
    _volumeUpLongPressTriggered = false;
    _volumeUpTimer = Timer(const Duration(milliseconds: 500), () {
      _triggerVolumeMax(context);
    });
  }

  /// 处理音量+抬起
  void handleVolumeUpPointerUp() {
    _volumeUpPointerDown = false;
    _volumeUpTimer?.cancel();
  }

  /// 处理音量-按下
  void handleVolumeDownPointerDown(BuildContext context) {
    _cancelVolumeDown();
    _volumeDownPointerDown = true;
    _volumeDownLongPressTriggered = false;
    _volumeDownTimer = Timer(const Duration(milliseconds: 500), () {
      _triggerVolumeMute(context);
    });
  }

  /// 处理音量-抬起
  void handleVolumeDownPointerUp() {
    _volumeDownPointerDown = false;
    _volumeDownTimer?.cancel();
  }

  /// 取消所有定时器
  void cancel() {
    _cancelVolumeUp();
    _cancelVolumeDown();
  }

  void _cancelVolumeUp() {
    _volumeUpPointerDown = false;
    _volumeUpTimer?.cancel();
    _volumeUpTimer = null;
  }

  void _cancelVolumeDown() {
    _volumeDownPointerDown = false;
    _volumeDownTimer?.cancel();
    _volumeDownTimer = null;
  }

  /// 触发音量设为最大
  Future<void> _triggerVolumeMax(BuildContext context) async {
    if (!_volumeUpPointerDown) return;
    _volumeUpLongPressTriggered = true;
    final actions = ref.read(deviceActionServiceProvider);
    try {
      final result = await actions.volumeMax(deviceId);
      if (context.mounted && _volumeUpPointerDown) {
        if (result.isSuccess) {
          _showFloatingMessage(context, '音量已设为最大');
        } else {
          _showFloatingMessage(context, '设置最大音量失败: ${result.message}', isError: true);
        }
      }
    } catch (e) {
      if (context.mounted && _volumeUpPointerDown) {
        _showFloatingMessage(context, '设置最大音量出错: $e', isError: true);
      }
    }
  }

  /// 触发音量设为静音
  Future<void> _triggerVolumeMute(BuildContext context) async {
    if (!_volumeDownPointerDown) return;
    _volumeDownLongPressTriggered = true;
    final actions = ref.read(deviceActionServiceProvider);
    try {
      final result = await actions.volumeMute(deviceId);
      if (context.mounted && _volumeDownPointerDown) {
        if (result.isSuccess) {
          _showFloatingMessage(context, '已静音');
        } else {
          _showFloatingMessage(context, '静音失败: ${result.message}', isError: true);
        }
      }
    } catch (e) {
      if (context.mounted && _volumeDownPointerDown) {
        _showFloatingMessage(context, '静音出错: $e', isError: true);
      }
    }
  }

  /// 显示提示消息
  void _showFloatingMessage(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xff09c47c),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }
}
