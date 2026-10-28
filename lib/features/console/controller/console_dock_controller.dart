import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 主窗口控制台的展开状态和用户选择的高度，不随设备或 Route 切换重置。
class ConsoleDockState {
  const ConsoleDockState({this.isOpen = false, this.height = 260});

  final bool isOpen;
  final double height;
}

final consoleDockProvider =
    NotifierProvider<ConsoleDockController, ConsoleDockState>(
      ConsoleDockController.new,
    );

/// 只管理布局；日志采集和跨窗口同步继续由 LogService 负责。
class ConsoleDockController extends Notifier<ConsoleDockState> {
  @override
  ConsoleDockState build() => const ConsoleDockState();

  void toggle() =>
      state = ConsoleDockState(isOpen: !state.isOpen, height: state.height);

  void close() => state = ConsoleDockState(height: state.height);

  void resize(double height) {
    if (!height.isFinite || height < 0) return;
    state = ConsoleDockState(isOpen: state.isOpen, height: height);
  }
}
