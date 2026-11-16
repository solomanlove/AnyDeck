part of 'app_settings_controller.dart';

/// 将设置变更同步到主窗口和其他已打开的子窗口。
mixin SettingsBroadcast on Notifier<AppSettings> {
  /// 主窗口向原生视频播放器同步主题；Flutter 子窗口沿用设置广播。
  Future<void> _syncVideoWindowAppearance(ThemeMode mode) async {
    if (!Platform.isMacOS || ref.read(windowIdProvider).isNotEmpty) return;
    try {
      await DlnaPlayerBridge.syncAppearance(mode);
    } catch (error) {
      debugPrint('Failed to sync video window appearance: $error');
    }
  }

  Future<void> _broadcastSettingChange(String method, Object value) async {
    final currentId = ref.read(windowIdProvider);
    if (currentId.isNotEmpty) {
      try {
        await AppSettingsController._mainSettingsChannel
            .invokeMethod(method, value)
            .timeout(const Duration(seconds: 15));
      } catch (error) {
        // 主窗口正在初始化或退出时，仍需尝试同步其余活动窗口。
        debugPrint('Failed to send setting change to main window: $error');
      }
    }

    final windows = await WindowController.getAll().timeout(
      const Duration(seconds: 15),
    );
    for (final window in windows) {
      if (window.windowId == currentId || window.arguments.isEmpty) {
        continue;
      }
      try {
        await window
            .invokeMethod(method, value)
            .timeout(const Duration(seconds: 15));
      } catch (error) {
        // 单个窗口关闭、通道未注册或无响应时，不阻断后续窗口的同步。
        debugPrint(
          'Failed to sync setting to window ${window.windowId}: $error',
        );
      }
    }
  }
}

/// 注册设置通道，供主窗口和各子窗口共用。
Future<void> _setupSettingsMethodHandler(
  String currentId,
  Future<dynamic> Function(MethodCall) handler,
) async {
  if (currentId.isEmpty) {
    await AppSettingsController._mainSettingsChannel.setMethodCallHandler(
      handler,
    );
    return;
  }
  SubWindowMethodDispatcher.registerHandler(handler);
  await SubWindowMethodDispatcher.ready;
}
