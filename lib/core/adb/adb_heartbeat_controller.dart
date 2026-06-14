import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'adb_device.dart';
import 'adb_service.dart';

/// 心跳频次自适应阶段枚举
enum HeartbeatPhase {
  /// 密集阶段：检测到变化或用户交互，每 2 秒心跳一次
  peak,

  /// 较密集阶段：每 1 分钟心跳一次
  high,

  /// 中频阶段：每 5 分钟心跳一次
  medium,

  /// 低频阶段：每 10 分钟心跳一次
  low,

  /// 停止阶段：完全暂停心跳，节省资源
  stopped,
}

/// 自适应 ADB 设备心跳控制器
/// 能够根据用户活跃度、设备插拔变化来智能降频或升频，避免多余的 CPU 背景消耗
class AdbHeartbeatController {
  final AdbService _adbService;
  final bool isSubWindow;
  
  // 广播流控制器，向外部订阅者分发设备列表
  final StreamController<List<AdbDevice>> _streamController = StreamController<List<AdbDevice>>.broadcast();
  
  Timer? _timer;
  DateTime _lastTriggerTime = DateTime.now();
  HeartbeatPhase _phase = HeartbeatPhase.peak;
  List<AdbDevice> _lastDevices = [];
  bool _isDisposed = false;
  bool _isPolling = false;

  AdbHeartbeatController({
    required AdbService adbService,
    this.isSubWindow = false,
  }) : _adbService = adbService {
    if (!isSubWindow) {
      // 启动时立即执行一次心跳，建立初始状态
      trigger();
    }
  }

  /// 获取设备列表数据流
  Stream<List<AdbDevice>> get deviceStream => _streamController.stream;

  /// 获取当前的心跳自适应阶段
  HeartbeatPhase get phase => _phase;

  /// 主动唤醒/重置心跳到密集状态 (Peak)
  void trigger() {
    if (_isDisposed || isSubWindow) return;
    _lastTriggerTime = DateTime.now();
    _phase = HeartbeatPhase.peak;
    
    // 立即安排下一次轮询，取消之前的定时器
    _scheduleNext(Duration.zero);
  }

  /// 释放资源，销毁定时器和流控制器
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _streamController.close();
  }

  /// 执行单次心跳检测（获取最新设备列表）
  Future<void> _poll() async {
    if (_isDisposed || _isPolling || isSubWindow) return;
    _isPolling = true;

    try {
      if (!kIsWeb) {
        final isVisible = await windowManager.isVisible();
        final isMinimized = await windowManager.isMinimized();
        if (!isVisible || isMinimized) {
          _isPolling = false;
          _updatePhaseAndSchedule();
          return;
        }
      }
    } catch (e) {
      debugPrint('Failed to check window visibility in heartbeat: $e');
    }

    try {
      final devices = await _adbService.listDevices();
      if (_isDisposed) return;

      // 比对最新的设备列表与上次列表是否有变化
      final hasChanged = !_sameDeviceList(_lastDevices, devices);
      _lastDevices = devices;
      _streamController.add(devices);

      if (hasChanged) {
        // 感应到变化（如设备插拔、授权状态变化）-> 重新激活密集心跳
        _lastTriggerTime = DateTime.now();
        _phase = HeartbeatPhase.peak;
      }
    } catch (error, stack) {
      if (!_isDisposed) {
        _streamController.addError(error, stack);
      }
    } finally {
      _isPolling = false;
    }

    // 根据自适应规则计算下一次的心跳间隔，并安排定时器
    _updatePhaseAndSchedule();
  }

  /// 根据自适应降频表，判断当前的阶段并调度下一次心跳
  void _updatePhaseAndSchedule() {
    if (_isDisposed) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastTriggerTime);
    Duration nextInterval;

    // 自适应判定规则：
    // 0s - 30s: 每 2 秒 (peak)
    // 30s - 5m: 每 1 分钟 (high)
    // 5m - 15m: 每 5 分钟 (medium)
    // 15m - 30m: 每 10 分钟 (low)
    // > 30m: 停止 (stopped)
    if (elapsed <= const Duration(seconds: 30)) {
      _phase = HeartbeatPhase.peak;
      nextInterval = const Duration(seconds: 2);
    } else if (elapsed <= const Duration(minutes: 5)) {
      _phase = HeartbeatPhase.high;
      nextInterval = const Duration(minutes: 1);
    } else if (elapsed <= const Duration(minutes: 15)) {
      _phase = HeartbeatPhase.medium;
      nextInterval = const Duration(minutes: 5);
    } else if (elapsed <= const Duration(minutes: 30)) {
      _phase = HeartbeatPhase.low;
      nextInterval = const Duration(minutes: 10);
    } else {
      _phase = HeartbeatPhase.stopped;
      _timer?.cancel();
      _timer = null;
      return;
    }

    _scheduleNext(nextInterval);
  }

  /// 调度下一次轮询任务
  void _scheduleNext(Duration interval) {
    _timer?.cancel();
    if (_isDisposed) return;

    if (interval == Duration.zero) {
      // 立即触发
      scheduleMicrotask(_poll);
    } else {
      _timer = Timer(interval, _poll);
    }
  }

  /// 比较两个设备列表内容是否完全一致（包括 ID、状态、型号等）
  bool _sameDeviceList(List<AdbDevice> previous, List<AdbDevice> next) {
    if (previous.length != next.length) {
      return false;
    }
    for (var index = 0; index < previous.length; index += 1) {
      final left = previous[index];
      final right = next[index];
      if (left.id != right.id ||
          left.status != right.status ||
          left.model != right.model ||
          left.product != right.product) {
        return false;
      }
    }
    return true;
  }
}
