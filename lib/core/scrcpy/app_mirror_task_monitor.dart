import 'dart:async';

import 'package:flutter/foundation.dart';

import '../adb/adb_service.dart';
import 'app_virtual_display_launcher.dart';

/// 目标应用在融合投屏会话中的 Task 位置。
enum AppMirrorTaskLocation { unknown, virtualDisplay, phone, missing }

/// 解析 Android RootTask；同一应用同时存在多个 Task 时，副屏优先。
AppMirrorTaskLocation locateAppMirrorTask(
  String output,
  String packageName,
  int virtualDisplayId,
) {
  final rootPattern = RegExp(
    r'^\s*(?:RootTask|Stack) id=\d+\b.*\bdisplayId=(\d+)',
  );
  final taskPattern = RegExp(
    r'^\s*taskId=\d+:\s+' + RegExp.escape(packageName) + r'/',
  );
  final displayIds = <int>{};
  int? currentDisplayId;
  bool hasRootTask = false;
  for (final line in output.split('\n')) {
    final root = rootPattern.firstMatch(line);
    if (root != null) {
      hasRootTask = true;
      currentDisplayId = int.tryParse(root.group(1)!);
    } else if (currentDisplayId != null && taskPattern.hasMatch(line)) {
      displayIds.add(currentDisplayId);
    }
  }
  if (displayIds.contains(virtualDisplayId)) {
    return AppMirrorTaskLocation.virtualDisplay;
  }
  if (displayIds.contains(0)) return AppMirrorTaskLocation.phone;
  return hasRootTask
      ? AppMirrorTaskLocation.missing
      : AppMirrorTaskLocation.unknown;
}

/// 低频检查应用是否离开副屏，并把用户主动重启的 Task 放回当前副屏。
class AppMirrorTaskMonitor extends ChangeNotifier {
  AppMirrorTaskMonitor({
    required this.adbService,
    required this.deviceId,
    required this.packageName,
    required this.virtualDisplayId,
    required this.isReady,
    this.interval = const Duration(seconds: 2),
  });

  final AdbService adbService;
  final String deviceId;
  final String packageName;
  final int? Function() virtualDisplayId;
  final bool Function() isReady;
  final Duration interval;

  Timer? _pollTimer;
  Timer? _restartGuardian;
  int? _observedDisplayId;
  int _missingSamples = 0;
  bool _checking = false;
  bool _restarting = false;
  bool _disposed = false;
  AppMirrorTaskLocation _location = AppMirrorTaskLocation.unknown;

  AppMirrorTaskLocation get location => _location;
  bool get isAway =>
      _location == AppMirrorTaskLocation.phone ||
      _location == AppMirrorTaskLocation.missing;
  bool get isRestarting => _restarting;

  void start() {
    if (_pollTimer != null || _disposed) return;
    _pollTimer = Timer.periodic(interval, (_) => unawaited(checkNow()));
    unawaited(checkNow());
  }

  /// 投屏重启或失败时清除旧 display 的位置，避免短暂显示过期占位页。
  void suspend() {
    _observedDisplayId = null;
    _missingSamples = 0;
    _restartGuardian?.cancel();
    _restartGuardian = null;
    _setLocation(AppMirrorTaskLocation.unknown);
  }

  Future<void> checkNow() async {
    if (_disposed || _checking || _restarting) return;
    final displayId = virtualDisplayId();
    if (displayId == null || !isReady()) {
      suspend();
      return;
    }
    if (_observedDisplayId != displayId) {
      _observedDisplayId = displayId;
      _missingSamples = 0;
      _setLocation(AppMirrorTaskLocation.unknown);
    }
    _checking = true;
    try {
      final result = await adbService.shellArgs(deviceId, [
        'cmd',
        'activity',
        'stack',
        'list',
      ], timeout: const Duration(seconds: 4));
      if (_disposed ||
          _restarting ||
          !isReady() ||
          virtualDisplayId() != displayId ||
          !result.isSuccess) {
        return;
      }
      final next = locateAppMirrorTask(result.stdout, packageName, displayId);
      if (next == AppMirrorTaskLocation.virtualDisplay) {
        _missingSamples = 0;
        _restartGuardian?.cancel();
        _restartGuardian = null;
        _setLocation(next);
      } else if (next == AppMirrorTaskLocation.phone) {
        _missingSamples = 0;
        _setLocation(next);
      } else if (next == AppMirrorTaskLocation.missing) {
        // Activity 切换期间可能短暂没有 Task，连续两次才显示占位页。
        if (++_missingSamples >= 2) _setLocation(next);
      } else {
        _missingSamples = 0;
      }
    } catch (_) {
      // 查询失败时保持已有画面状态，下一轮再检查。
    } finally {
      _checking = false;
    }
  }

  /// 复用现有虚拟屏，优先迁移手机上的 Task，避免清除页面状态。
  Future<void> restartOnVirtualDisplay() async {
    if (_disposed || _restarting) return;
    final displayId = virtualDisplayId();
    if (displayId == null || !isReady()) {
      throw StateError('Virtual display is unavailable');
    }
    _restarting = true;
    notifyListeners();
    try {
      _restartGuardian?.cancel();
      final guardian = await launchAppOnVirtualDisplay(
        adbService: adbService,
        deviceId: deviceId,
        packageName: packageName,
        displayIdFuture: Future.value(displayId),
      );
      if (_disposed) {
        guardian.cancel();
        return;
      }
      _restartGuardian = guardian;
      _missingSamples = 0;
    } finally {
      _restarting = false;
      if (!_disposed) {
        notifyListeners();
        unawaited(checkNow());
      }
    }
  }

  void _setLocation(AppMirrorTaskLocation value) {
    if (_disposed || _location == value) return;
    _location = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _restartGuardian?.cancel();
    super.dispose();
  }
}
