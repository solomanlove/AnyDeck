import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dal/rust_dal_bridge.dart';

/// 蓝牙虚拟鼠标状态
enum BleMouseState {
  stopped(0),
  advertising(1),
  connected(2);

  final int rawValue;
  const BleMouseState(this.rawValue);

  static BleMouseState fromRaw(int value) {
    switch (value) {
      case 1:
        return BleMouseState.advertising;
      case 2:
        return BleMouseState.connected;
      default:
        return BleMouseState.stopped;
    }
  }
}

/// BLE 鼠标运行状态模型
class IosBleMouseState {
  const IosBleMouseState({
    this.isEnabled = false,
    this.state = BleMouseState.stopped,
    this.sensitivity = 1.0,
  });

  final bool isEnabled;
  final BleMouseState state;
  final double sensitivity;

  IosBleMouseState copyWith({
    bool? isEnabled,
    BleMouseState? state,
    double? sensitivity,
  }) {
    return IosBleMouseState(
      isEnabled: isEnabled ?? this.isEnabled,
      state: state ?? this.state,
      sensitivity: sensitivity ?? this.sensitivity,
    );
  }
}

/// iOS 蓝牙 HID 鼠标模拟状态管理器。
/// 通过 Rust 底层调用 macOS CoreBluetooth / 平台标准 BLE HID 规范，
/// 将桌面端模拟为标准蓝牙鼠标并广播，让 iPhone 辅助触控 (AssistiveTouch) 无线免越狱反控。
class IosBleMouseNotifier extends Notifier<IosBleMouseState> {
  IosBleMouseNotifier({RustDalBridge? bridge})
      : _bridge = bridge ?? RustDalBridge.instance;

  final RustDalBridge _bridge;
  Timer? _statusPollTimer;
  bool _isSimulatorStarted = false;

  Offset? _lastPointerPosition;
  bool _leftPressed = false;
  bool _rightPressed = false;
  bool _middlePressed = false;

  @override
  IosBleMouseState build() {
    ref.onDispose(() {
      _statusPollTimer?.cancel();
      if (_isSimulatorStarted && _bridge.isAvailable) {
        _bridge.bleMouseStop();
      }
    });
    return const IosBleMouseState();
  }

  /// 设置灵敏度 (0.2 ~ 5.0)
  void setSensitivity(double value) {
    state = state.copyWith(sensitivity: value.clamp(0.2, 5.0));
  }

  /// 切换蓝牙鼠标服务启停
  Future<bool> toggle() async {
    if (state.isEnabled) {
      return stop();
    } else {
      return start();
    }
  }

  /// 启动蓝牙广播模拟鼠标
  Future<bool> start() async {
    if (!_bridge.isAvailable) {
      debugPrint('[IosBleMouseNotifier] RustDalBridge 不可用，无法启动 BLE HID 鼠标');
      return false;
    }

    final success = _bridge.bleMouseStart();
    if (success) {
      _isSimulatorStarted = true;
      state = state.copyWith(isEnabled: true);
      _updateStatus();
      _startStatusPolling();
      debugPrint('[IosBleMouseNotifier] BLE HID 鼠标广播已启动');
    }
    return success;
  }

  /// 停止蓝牙模拟鼠标
  Future<bool> stop() async {
    _statusPollTimer?.cancel();
    _statusPollTimer = null;
    _lastPointerPosition = null;
    _leftPressed = false;
    _rightPressed = false;
    _middlePressed = false;

    if (_bridge.isAvailable) {
      _bridge.bleMouseStop();
    }
    _isSimulatorStarted = false;

    state = state.copyWith(isEnabled: false, state: BleMouseState.stopped);
    debugPrint('[IosBleMouseNotifier] BLE HID 鼠标已停止');
    return true;
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!state.isEnabled) return;
      _updateStatus();
    });
  }

  void _updateStatus() {
    if (!_bridge.isAvailable) return;
    final statusCode = _bridge.bleMouseStatus();
    final newState = BleMouseState.fromRaw(statusCode);
    if (newState != state.state) {
      state = state.copyWith(state: newState);
    }
  }

  /// 当前按键位掩码: 1: 左键, 2: 右键, 4: 中键
  int get _currentButtonsMask {
    int mask = 0;
    if (_leftPressed) mask |= 0x01;
    if (_rightPressed) mask |= 0x02;
    if (_middlePressed) mask |= 0x04;
    return mask;
  }

  /// 处理鼠标按下事件
  void handlePointerDown(PointerDownEvent event) {
    if (!state.isEnabled) return;
    _lastPointerPosition = event.localPosition;

    if (event.buttons & kPrimaryMouseButton != 0) {
      _leftPressed = true;
    }
    if (event.buttons & kSecondaryMouseButton != 0) {
      _rightPressed = true;
    }
    if (event.buttons & kMiddleMouseButton != 0) {
      _middlePressed = true;
    }

    _sendHidReport(dx: 0, dy: 0);
  }

  /// 处理鼠标移动/拖拽事件
  void handlePointerMove(PointerMoveEvent event) {
    if (!state.isEnabled) return;

    int dx = 0;
    int dy = 0;

    if (_lastPointerPosition != null) {
      final delta = event.localPosition - _lastPointerPosition!;
      dx = (delta.dx * state.sensitivity).round().clamp(-127, 127);
      dy = (delta.dy * state.sensitivity).round().clamp(-127, 127);
    } else {
      dx = (event.delta.dx * state.sensitivity).round().clamp(-127, 127);
      dy = (event.delta.dy * state.sensitivity).round().clamp(-127, 127);
    }

    _lastPointerPosition = event.localPosition;
    _sendHidReport(dx: dx, dy: dy);
  }

  /// 处理鼠标抬起事件
  void handlePointerUp(PointerUpEvent event) {
    if (!state.isEnabled) return;
    _lastPointerPosition = null;

    _leftPressed = false;
    _rightPressed = false;
    _middlePressed = false;

    _sendHidReport(dx: 0, dy: 0);
  }

  /// 处理滚轮滑动
  void handlePointerScroll(PointerScrollEvent event) {
    if (!state.isEnabled) return;
    final wheel = (-event.scrollDelta.dy / 20).round().clamp(-127, 127);
    _sendHidReport(dx: 0, dy: 0, wheel: wheel);
  }

  /// 发送底层 HID Report
  void _sendHidReport({required int dx, required int dy, int wheel = 0}) {
    if (!_bridge.isAvailable) return;
    _bridge.bleMouseSend(
      buttons: _currentButtonsMask,
      dx: dx,
      dy: dy,
      wheel: wheel,
    );
  }
}

/// 全局共享的 iOS 蓝牙鼠标状态 Provider
final iosBleMouseProvider =
    NotifierProvider<IosBleMouseNotifier, IosBleMouseState>(
  IosBleMouseNotifier.new,
);

final iosBleMouseServiceProvider = iosBleMouseProvider;
