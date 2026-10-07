import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ios_control_gateway.dart';

/// 状态使用 iOS point 尺寸；像素帧尺寸只负责绘制，不混入输入坐标。
class IosControlState {
  const IosControlState({
    this.ready = false,
    this.busy = false,
    this.width = 0,
    this.height = 0,
    this.orientation = '',
    this.error,
  });
  final bool ready;
  final bool busy;
  final double width;
  final double height;
  final String orientation;
  final String? error;
}

/// 界面仅订阅状态，所有真实动作统一经主窗口 gateway 路由。
class IosControlNotifier extends Notifier<IosControlState> {
  IosControlNotifier(this.udid);
  final String udid;
  Timer? _timer;
  bool _polling = false;
  int _actionGeneration = 0;

  @override
  IosControlState build() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(refresh);
    return const IosControlState();
  }

  Future<void> refresh() async {
    if (!ref.mounted || state.busy || _polling) return;
    _polling = true;
    try {
      var value = await IosControlGateway.call(udid, 'status');
      if (value['ready'] == true && value['busy'] != true) {
        value = await IosControlGateway.call(udid, 'geometry');
      }
      if (ref.mounted && !state.busy) _apply(value, error: state.error);
    } catch (error) {
      if (ref.mounted &&
          !state.busy &&
          !error.toString().contains('iosControlBusy')) {
        state = IosControlState(error: error.toString());
      }
    } finally {
      _polling = false;
    }
  }

  void _apply(Map<String, dynamic> value, {String? error}) {
    state = IosControlState(
      ready: value['ready'] == true,
      busy: false,
      width: (value['width'] as num?)?.toDouble() ?? state.width,
      height: (value['height'] as num?)?.toDouble() ?? state.height,
      orientation: value['orientation'] as String? ?? state.orientation,
      error: error,
    );
  }

  Future<bool> perform(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (state.busy && action != 'stop') return false;
    final generation = ++_actionGeneration;
    state = IosControlState(
      ready: state.ready,
      busy: true,
      width: state.width,
      height: state.height,
      orientation: state.orientation,
    );
    try {
      final value = await IosControlGateway.call(udid, action, args);
      if (ref.mounted && generation == _actionGeneration) _apply(value);
      return true;
    } catch (error) {
      if (ref.mounted && generation == _actionGeneration) {
        state = IosControlState(
          ready: state.ready,
          width: state.width,
          height: state.height,
          orientation: state.orientation,
          error: error.toString(),
        );
      }
      return false;
    }
  }
}

final iosControlProvider = NotifierProvider.autoDispose
    .family<IosControlNotifier, IosControlState, String>(
      IosControlNotifier.new,
    );
