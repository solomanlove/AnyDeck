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
      await AppSettingsController._mainSettingsChannel.invokeMethod(
        method,
        value,
      );
    }

    final windows = await WindowController.getAll();
    for (final window in windows) {
      if (window.windowId == currentId || window.arguments.isEmpty) {
        continue;
      }
      await window.invokeMethod(method, value);
    }
  }
}

/// 注册设置通道，供主窗口和各子窗口共用。
void _setupSettingsMethodHandler(
  String currentId,
  Future<dynamic> Function(MethodCall) handler,
) {
  if (currentId.isEmpty) {
    unawaited(AppSettingsController._mainSettingsChannel.setMethodCallHandler(handler));
    return;
  }
  SubWindowMethodDispatcher.registerHandler(handler);
}
