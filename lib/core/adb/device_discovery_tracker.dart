import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../harmony/hdc_service.dart';
import '../ios/ios_device_service.dart';
import 'discovered_device.dart';
import 'adb_service.dart';

/// 主窗口常驻的设备发现聚合器，汇总 ADB、HDC 与 iOS 设备。
/// ADB 使用 `adb track-devices -l` 监听，HDC 与 iOS 定时检测并支持主动刷新。
/// 隐藏窗口、最小化、切换 Tab 均保持持续监听，退出应用时释放。
class DeviceDiscoveryTracker {
  DeviceDiscoveryTracker({
    required AdbService adbService,
    IosDeviceService? iosDeviceService,
    HdcService? hdcService,
    this.isSubWindow = false,
  })  : _adbService = adbService,
        _iosDeviceService = iosDeviceService,
        _hdcService = hdcService {
    if (!isSubWindow) {
      _startTracking();
    }
  }

  final AdbService _adbService;
  final IosDeviceService? _iosDeviceService;
  final HdcService? _hdcService;
  final bool isSubWindow;

  final _streamController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  Process? _trackProcess;
  Timer? _reconnectTimer;
  Timer? _iosPollTimer;
  Timer? _harmonyPollTimer;
  Future<List<DiscoveredDevice>>? _harmonyRefresh;
  bool _iosPolling = false;
  bool _isDisposed = false;

  List<DiscoveredDevice> _androidDevices = [];
  List<DiscoveredDevice> _iosDevices = [];
  List<DiscoveredDevice> _harmonyDevices = [];
  List<DiscoveredDevice> _lastPublished = [];

  Stream<List<DiscoveredDevice>> get deviceStream => _streamController.stream;

  List<DiscoveredDevice> get currentDevices => _lastPublished;

  Future<void> _startTracking() async {
    if (_isDisposed || isSubWindow) return;

    // HDC 独立启动，避免 ADB/iOS 初始化失败或慢查询阻塞鸿蒙设备发现。
    _startHarmonyPolling();

    // 先同步拉取一次初始设备列表，避免等待 track-devices 首个事件有延迟
    try {
      _androidDevices = await _adbService.listDevices();
      await _pollIosDevices();
      _publish();
    } catch (e) {
      debugPrint('[DeviceDiscoveryTracker] initial listDevices error: $e');
    }

    _startAdbTrackProcess();
    _startIosPolling();
  }

  void _startAdbTrackProcess() async {
    if (_isDisposed || isSubWindow) return;

    try {
      final process = await _adbService.start(['track-devices', '-l']);
      // 子窗口可能在启动命令返回前关闭，迟到的监听进程也必须回收。
      if (_isDisposed) {
        process.kill();
        return;
      }
      _trackProcess = process;

      // 缓冲区用于处理 TCP/管道分包和粘包
      var buffer = '';

      process.stdout.transform(utf8.decoder).listen(
        (chunk) {
          buffer += chunk;

          while (true) {
            if (buffer.isEmpty) break;

            // 忽略类似 "* daemon started successfully *" 的 adb 服务端提示行
            if (buffer.startsWith('*')) {
              final newlineIndex = buffer.indexOf('\n');
              if (newlineIndex != -1) {
                buffer = buffer.substring(newlineIndex + 1);
                continue;
              } else {
                break;
              }
            }

            // ADB track-devices 协议规定每个批次以 4 字节十六进制字符开头表示数据长度
            if (buffer.length < 4) break;

            final lenStr = buffer.substring(0, 4);
            final length = int.tryParse(lenStr, radix: 16);
            if (length == null) {
              // 遇到异常非十六进制前缀，跳到下一行继续尝试
              final newlineIndex = buffer.indexOf('\n');
              if (newlineIndex != -1) {
                buffer = buffer.substring(newlineIndex + 1);
                continue;
              } else {
                buffer = '';
                break;
              }
            }

            // 检查当前缓冲区是否已收齐该批次的完整数据
            if (buffer.length < 4 + length) {
              break;
            }

            final payload = buffer.substring(4, 4 + length);
            buffer = buffer.substring(4 + length);

            final lines = payload.split('\n');
            final devices = <DiscoveredDevice>[];
            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) continue;
              final device = _adbService.parseDeviceLine(trimmed);
              if (device != null) {
                devices.add(device);
              }
            }

            _androidDevices = List.unmodifiable(devices);
            _publish();
          }
        },
        onError: (err) {
          debugPrint('[DeviceDiscoveryTracker] track-devices stream error: $err');
          _scheduleRestart();
        },
        onDone: () {
          debugPrint('[DeviceDiscoveryTracker] track-devices process finished');
          _scheduleRestart();
        },
      );
    } catch (e) {
      debugPrint('[DeviceDiscoveryTracker] failed to start track-devices: $e');
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    if (_isDisposed || isSubWindow) return;
    _trackProcess?.kill();
    _trackProcess = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      _startAdbTrackProcess();
    });
  }

  void _startIosPolling() {
    _iosPollTimer?.cancel();
    if (_iosDeviceService == null) return;
    _iosPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await refreshIosDevices();
    });
  }

  /// iOS 发现请求串行化；慢查询期间到来的定时 tick 直接跳过。
  Future<void> refreshIosDevices() async {
    if (_iosPolling || _isDisposed) return;
    await _pollIosDevices();
    _publish();
  }

  Future<void> _pollIosDevices() async {
    if (_iosPolling || _isDisposed) return;
    _iosPolling = true;
    try {
      if (_iosDeviceService != null) {
        _iosDevices = await _iosDeviceService.listDevices();
      }
    } catch (e) {
      debugPrint('[DeviceDiscoveryTracker] iOS poll error: $e');
    } finally {
      _iosPolling = false;
    }
  }

  /// HDC 无设备事件流，每 2 秒检测一次；隐藏窗口和切换 Tab 后仍持续检测。
  void _startHarmonyPolling() {
    if (_isDisposed || isSubWindow || _hdcService == null) return;
    _harmonyPollTimer?.cancel();
    unawaited(refreshHarmonyDevices());
    _harmonyPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(refreshHarmonyDevices());
    });
  }

  /// 自动检测和手动刷新共用在途请求，避免慢查询堆积及旧结果覆盖新结果。
  Future<List<DiscoveredDevice>> refreshHarmonyDevices({bool publish = true}) async {
    if (_isDisposed) return _harmonyDevices;
    final refresh = _harmonyRefresh ??= _pollHarmonyDevices();
    try {
      final devices = await refresh;
      if (publish) _publish();
      return devices;
    } finally {
      if (identical(_harmonyRefresh, refresh)) _harmonyRefresh = null;
    }
  }

  Future<List<DiscoveredDevice>> _pollHarmonyDevices() async {
    try {
      if (_hdcService != null) {
        final devices = await _hdcService.listDevices();
        // 退出后迟到的结果不能再修改快照或向已关闭的 Stream 发布。
        if (!_isDisposed) _harmonyDevices = devices;
      }
    } catch (e) {
      debugPrint('[DeviceDiscoveryTracker] HarmonyOS refresh error: $e');
    }
    return _harmonyDevices;
  }

  void _publish() {
    if (_isDisposed) return;
    final all = [..._androidDevices, ..._iosDevices, ..._harmonyDevices];
    if (!_sameDeviceList(_lastPublished, all)) {
      _lastPublished = all;
      _streamController.add(all);
    }
  }

  bool _sameDeviceList(List<DiscoveredDevice> a, List<DiscoveredDevice> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].status != b[i].status ||
          a[i].model != b[i].model ||
          a[i].product != b[i].product) {
        return false;
      }
    }
    return true;
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _iosPollTimer?.cancel();
    _harmonyPollTimer?.cancel();
    _trackProcess?.kill();
    _trackProcess = null;
    _streamController.close();
  }
}
