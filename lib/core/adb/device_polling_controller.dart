import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import '../ios/ios_device_service.dart';
import 'discovered_device.dart';
import 'adb_service.dart';

/// 轮询频次自适应阶段枚举
enum DevicePollingPhase {
  /// 密集阶段：检测到变化或用户交互，每 2 秒轮询一次
  peak,

  /// 较密集阶段：每 1 分钟轮询一次
  high,

  /// 中频阶段：每 5 分钟轮询一次
  medium,

  /// 低频阶段：每 10 分钟轮询一次
  low,

  /// 停止阶段：完全暂停轮询，节省资源
  stopped,
}

/// ADB 与 iOS 设备列表的自适应轮询控制器
/// 能够根据用户活跃度、设备插拔变化来智能降频或升频，避免多余的 CPU 背景消耗
class DevicePollingController {
  final AdbService _adbService;
  final IosDeviceService? _iosDeviceService;
  final bool isSubWindow;
  final bool isDeviceListVisible;
  
  // 广播流控制器，向外部订阅者分发设备列表
  final StreamController<List<DiscoveredDevice>> _streamController = StreamController<List<DiscoveredDevice>>.broadcast();
  
  Timer? _timer;
  DateTime _lastTriggerTime = DateTime.now();
  DevicePollingPhase _phase = DevicePollingPhase.peak;
  List<DiscoveredDevice> _lastDevices = [];
  bool _isDisposed = false;
  bool _isPolling = false;

  DevicePollingController({
    required AdbService adbService,
    IosDeviceService? iosDeviceService,
    this.isSubWindow = false,
    this.isDeviceListVisible = true,
  }) : _adbService = adbService,
       _iosDeviceService = iosDeviceService {
    if (!isSubWindow && isDeviceListVisible) {
      // 启动时立即执行一次轮询，建立初始状态
      trigger();
    }
  }

  /// 获取设备列表数据流
  Stream<List<DiscoveredDevice>> get deviceStream => _streamController.stream;

  /// 获取当前的轮询自适应阶段
  DevicePollingPhase get phase => _phase;

  /// 主动唤醒/重置轮询到密集状态 (Peak)
  void trigger() {
    if (_isDisposed || isSubWindow || !isDeviceListVisible) return;
    _lastTriggerTime = DateTime.now();
    _phase = DevicePollingPhase.peak;
    
    // 立即安排下一次轮询，取消之前的定时器
    _scheduleNext(Duration.zero);
  }

  /// 释放资源，销毁定时器和流控制器
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _streamController.close();
  }

  /// 执行单次轮询检测（获取最新设备列表）
  Future<void> _poll() async {
    if (_isDisposed || _isPolling || isSubWindow || !isDeviceListVisible) return;
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
      final androidDevices = await _adbService.listDevices();
      List<DiscoveredDevice> iosDevices = [];
      if (_iosDeviceService != null) {
        iosDevices = await _iosDeviceService.listDevices();
      }
      final devices = [...androidDevices, ...iosDevices];
      if (_isDisposed) return;

      // 比对最新的设备列表与上次列表是否有变化
      final hasChanged = !_sameDeviceList(_lastDevices, devices);
      _lastDevices = devices;
      _streamController.add(devices);

      if (hasChanged) {
        // 感应到变化（如设备插拔、授权状态变化）-> 重新激活密集轮询
        _lastTriggerTime = DateTime.now();
        _phase = DevicePollingPhase.peak;
      }
    } catch (error, stack) {
      if (!_isDisposed) {
        _streamController.addError(error, stack);
      }
    } finally {
      _isPolling = false;
    }

    // 根据自适应规则计算下一次的轮询间隔，并安排定时器
    _updatePhaseAndSchedule();
  }

  /// 根据自适应降频表，判断当前的阶段并调度下一次轮询
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
      _phase = DevicePollingPhase.peak;
      nextInterval = const Duration(seconds: 2);
    } else if (elapsed <= const Duration(minutes: 5)) {
      _phase = DevicePollingPhase.high;
      nextInterval = const Duration(minutes: 1);
    } else if (elapsed <= const Duration(minutes: 15)) {
      _phase = DevicePollingPhase.medium;
      nextInterval = const Duration(minutes: 5);
    } else if (elapsed <= const Duration(minutes: 30)) {
      _phase = DevicePollingPhase.low;
      nextInterval = const Duration(minutes: 10);
    } else {
      _phase = DevicePollingPhase.stopped;
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
  bool _sameDeviceList(List<DiscoveredDevice> previous, List<DiscoveredDevice> next) {
    if (previous.length != next.length) {
      return false;
    }
    for (var index = 0; index < previous.length; index += 1) {
      final left = previous[index];
      final right = next[index];
      if (left.id != right.id ||
          left.status != right.status ||
          left.model != right.model ||
          left.product != right.product ||
          !setEquals(left.iosConnectionTypes, right.iosConnectionTypes) ||
          left.isIos != right.isIos) {
        return false;
      }
    }
    return true;
  }
}
