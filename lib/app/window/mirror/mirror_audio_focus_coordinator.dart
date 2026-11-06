import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

/// 投屏窗口的设备级音频焦点协调器。
///
/// scrcpy 采集的是整台设备音频，同一设备只允许一个投屏窗口播放；
/// 新打开的单 App 窗口优先获得焦点，关闭后再恢复其他投屏窗口。
class MirrorAudioFocusCoordinator {
  static const methodName = 'setMirrorAudioMuted';

  /// 申请当前窗口的音频状态，返回当前窗口是否应初始静音。
  Future<bool> claim({
    required String currentWindowId,
    required String deviceId,
    String? physicalDeviceKey,
    required bool isAppMirror,
  }) async {
    final others = await _matchingWindows(currentWindowId, deviceId, physicalDeviceKey);
    if (isAppMirror) {
      // 两个 App 窗口同时初始化时，各自独立算出同一个获胜者。
      final appIds = [
        currentWindowId,
        ...others.where((window) => window.isAppMirror)
            .map((window) => window.controller.windowId),
      ]..sort(_compareWindowIds);
      final winnerId = appIds.last;
      for (final window in others) {
        await _setMuted(
          window.controller,
          deviceId,
          physicalDeviceKey,
          window.controller.windowId != winnerId,
        );
      }
      return currentWindowId != winnerId;
    }

    // 整机投屏后打开时不抢占已有窗口的音频，防止双重播放。
    return others.isNotEmpty;
  }

  /// 当前窗口关闭后重新选择音频拥有者。
  Future<void> release({
    required String currentWindowId,
    required String deviceId,
    String? physicalDeviceKey,
  }) async {
    final others = await _matchingWindows(currentWindowId, deviceId, physicalDeviceKey);
    if (others.isEmpty) return;

    final appMirrors = others.where((window) => window.isAppMirror).toList()
      ..sort((a, b) => _compareWindowIds(
        a.controller.windowId, b.controller.windowId,
      ));
    final winner = appMirrors.isNotEmpty ? appMirrors.last : others.first;
    for (final window in others) {
      await _setMuted(
        window.controller,
        deviceId,
        physicalDeviceKey,
        window.controller.windowId != winner.controller.windowId,
      );
    }
  }

  /// desktop_multi_window 的数字 ID 按创建顺序比较；其他 ID 仍保持确定性。
  int _compareWindowIds(String left, String right) {
    final leftNumber = int.tryParse(left);
    final rightNumber = int.tryParse(right);
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    return left.compareTo(right);
  }

  Future<List<_MirrorWindow>> _matchingWindows(
    String currentWindowId,
    String deviceId,
    String? physicalDeviceKey,
  ) async {
    try {
      final windows = await WindowController.getAll();
      final matches = <_MirrorWindow>[];
      for (final window in windows) {
        if (window.windowId == currentWindowId || window.arguments.isEmpty) {
          continue;
        }
        try {
          final arguments = jsonDecode(window.arguments);
          if (arguments is! Map ||
              arguments['type'] != 'mirror' ||
              (arguments['deviceId'] != deviceId &&
                  (physicalDeviceKey == null || arguments['physicalDeviceKey'] != physicalDeviceKey)) ||
              arguments['isIos'] == true ||
              arguments['isHarmony'] == true) {
            continue;
          }
          matches.add(
            _MirrorWindow(
              controller: window,
              isAppMirror: arguments['startApp'] is String,
            ),
          );
        } catch (e) {
          debugPrint('Failed to parse mirror window arguments: $e');
        }
      }
      return matches;
    } catch (e) {
      debugPrint('Failed to inspect mirror audio windows: $e');
      return const [];
    }
  }

  Future<void> _setMuted(
    WindowController controller,
    String deviceId,
    String? physicalDeviceKey,
    bool muted,
  ) async {
    try {
      await controller.invokeMethod(methodName, {
        'deviceId': deviceId,
        'physicalDeviceKey': physicalDeviceKey,
        'muted': muted,
      });
    } catch (e) {
      debugPrint('Failed to update mirror audio focus: $e');
    }
  }
}

class _MirrorWindow {
  const _MirrorWindow({required this.controller, required this.isAppMirror});

  final WindowController controller;
  final bool isAppMirror;
}
