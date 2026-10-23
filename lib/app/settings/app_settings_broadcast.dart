part of 'app_settings_controller.dart';

/// 将设置变更同步到主窗口和其他已打开的子窗口。
mixin SettingsBroadcast on Notifier<AppSettings> {
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
