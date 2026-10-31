import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../harmony/hdc_service.dart';
import '../ios/ios_device_service.dart';
import 'discovered_device.dart';
import 'adb_service.dart';

/// 主窗口常驻的设备监听器，通过 `AdbService.start` 管理 `adb track-devices -l` 进程。
/// 隐藏窗口、最小化、切换 Tab 均保持持续监听，退出应用时释放。
class AdbDeviceTracker {
  AdbDeviceTracker({
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
  bool _isDisposed = false;

  List<DiscoveredDevice> _androidDevices = [];
  List<DiscoveredDevice> _iosDevices = [];
  List<DiscoveredDevice> _harmonyDevices = [];
  List<DiscoveredDevice> _lastPublished = [];

  Stream<List<DiscoveredDevice>> get deviceStream => _streamController.stream;

  List<DiscoveredDevice> get currentDevices => _lastPublished;

  Future<void> _startTracking() async {
    if (_isDisposed || isSubWindow) return;

    // 先同步拉取一次初始设备列表，避免等待 track-devices 首个事件有延迟
    try {
      _androidDevices = await _adbService.listDevices();
      await _pollIosDevices();
      await refreshHarmonyDevices(publish: false);
      _publish();
    } catch (e) {
      debugPrint('[AdbDeviceTracker] initial listDevices error: $e');
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
          debugPrint('[AdbDeviceTracker] track-devices stream error: $err');
          _scheduleRestart();
        },
        onDone: () {
          debugPrint('[AdbDeviceTracker] track-devices process finished');
          _scheduleRestart();
        },
      );
    } catch (e) {
      debugPrint('[AdbDeviceTracker] failed to start track-devices: $e');
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
      if (_isDisposed) return;
      await _pollIosDevices();
      _publish();
    });
  }

  Future<void> _pollIosDevices() async {
    try {
      if (_iosDeviceService != null) {
        _iosDevices = await _iosDeviceService.listDevices();
      }
    } catch (e) {
      debugPrint('[AdbDeviceTracker] iOS poll error: $e');
    }
  }

  /// HDC 不支持设备事件流，仅在初始化或显式刷新时查询一次。
  Future<List<DiscoveredDevice>> refreshHarmonyDevices({bool publish = true}) async {
    try {
      if (_hdcService != null) {
        _harmonyDevices = await _hdcService.listDevices();
      }
    } catch (e) {
      debugPrint('[AdbDeviceTracker] HarmonyOS refresh error: $e');
    }
    if (publish) {
      _publish();
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
    _trackProcess?.kill();
    _trackProcess = null;
    _streamController.close();
  }
}
