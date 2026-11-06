part of 'screenshot_controller.dart';

/// 自动截图采用单次定时器；上一张结束后才安排下一张。
mixin ScreenshotAutoRefresh on Notifier<ScreenshotLayoutState> {
  Timer? _autoRefreshTimer;
  int _autoRefreshGeneration = 0;

  Future<void> captureScreenshot({bool isAuto = false});

  void _startAutoRefreshTimer() {
    _cancelAutoRefreshTimer();
    _scheduleAutoRefresh(++_autoRefreshGeneration);
  }

  /// 上次自动截图结束后再排下一次，避免设备变慢时累积截图与解码任务。
  void _scheduleAutoRefresh(int generation) {
    final interval = state.autoRefreshInterval > 0
        ? state.autoRefreshInterval
        : 3;
    _autoRefreshTimer = Timer(Duration(seconds: interval), () async {
      _autoRefreshTimer = null;
      if (generation != _autoRefreshGeneration ||
          !ref.mounted ||
          !state.isAutoRefresh) {
        return;
      }
      await captureScreenshot(isAuto: true);
      if (generation == _autoRefreshGeneration &&
          ref.mounted &&
          state.isAutoRefresh) {
        _scheduleAutoRefresh(generation);
      }
    });
  }

  void _cancelAutoRefreshTimer() {
    _autoRefreshGeneration++;
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }
}
