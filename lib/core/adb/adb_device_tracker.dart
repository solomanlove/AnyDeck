import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../harmony/hdc_service.dart';
import '../ios/ios_device_service.dart';
import 'adb_device.dart';
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
      StreamController<List<AdbDevice>>.broadcast();

  Process? _trackProcess;
  Timer? _reconnectTimer;
  Timer? _auxiliaryPollTimer;
  bool _isDisposed = false;

  List<AdbDevice> _androidDevices = [];
  List<AdbDevice> _iosDevices = [];
  List<AdbDevice> _harmonyDevices = [];
  List<AdbDevice> _lastPublished = [];

  Stream<List<AdbDevice>> get deviceStream => _streamController.stream;

  List<AdbDevice> get currentDevices => _lastPublished;

  Future<void> _startTracking() async {
    if (_isDisposed || isSubWindow) return;

    // 先同步拉取一次初始设备列表，避免等待 track-devices 首个事件有延迟
    try {
      _androidDevices = await _adbService.listDevices();
      await _pollAuxiliaryDevices();
      _publish();
    } catch (e) {
      debugPrint('[AdbDeviceTracker] initial listDevices error: $e');
    }

    _startAdbTrackProcess();
    _startAuxiliaryPolling();
  }

  void _startAdbTrackProcess() async {
    if (_isDisposed || isSubWindow) return;

    try {
      final process = await _adbService.start(['track-devices', '-l']);
      _trackProcess = process;

      // 监听 stdout 数据流
      final lineStream = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      var currentBatch = <AdbDevice>[];
      Timer? debounceTimer;

      lineStream.listen(
        (line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return;
          // 忽略类似 "* daemon started successfully *" 的输出
          if (trimmed.startsWith('*')) return;

          final device = _adbService.parseDeviceLine(trimmed);
          if (device != null) {
            currentBatch.add(device);
          }

          // 使用 50ms 聚合单次 track-devices 刷新的全部设备行
          debounceTimer?.cancel();
          debounceTimer = Timer(const Duration(milliseconds: 50), () {
            _androidDevices = List.unmodifiable(currentBatch);
            currentBatch = [];
            _publish();
          });
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

  void _startAuxiliaryPolling() {
    _auxiliaryPollTimer?.cancel();
    // iOS 与鸿蒙设备每 5 秒轮询一次
    _auxiliaryPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_isDisposed) return;
      await _pollAuxiliaryDevices();
      _publish();
    });
  }

  Future<void> _pollAuxiliaryDevices() async {
    try {
      if (_iosDeviceService != null) {
        _iosDevices = await _iosDeviceService.listDevices();
      }
      if (_hdcService != null) {
        _harmonyDevices = await _hdcService.listDevices();
      }
    } catch (e) {
      debugPrint('[AdbDeviceTracker] auxiliary poll error: $e');
    }
  }

  void _publish() {
    if (_isDisposed) return;
    final all = [..._androidDevices, ..._iosDevices, ..._harmonyDevices];
    if (!_sameDeviceList(_lastPublished, all)) {
      _lastPublished = all;
      _streamController.add(all);
    }
  }

  bool _sameDeviceList(List<AdbDevice> a, List<AdbDevice> b) {
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
    _auxiliaryPollTimer?.cancel();
    _trackProcess?.kill();
    _trackProcess = null;
    _streamController.close();
  }
}
