part of 'app_settings_controller.dart';

/// 通知与互传目录设置沿用统一持久化、跨窗口广播入口。
mixin NotificationSettings on Notifier<AppSettings>, SettingsBroadcast {
  Future<void> setDeviceConnectNotification(
    bool value, {
    bool broadcast = true,
  }) async {
    state = state.copyWith(deviceConnectNotification: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      AppSettingsController._deviceConnectNotificationKey,
      value,
    );
    if (broadcast) {
      try {
        await _broadcastSettingChange(
          'update_device_connect_notification',
          value,
        );
      } catch (e) {
        debugPrint(
          'Failed to broadcast device connect notification change: $e',
        );
      }
    }
  }

  Future<void> setNotificationBodyPreview(
    bool value, {
    bool broadcast = true,
  }) async {
    state = state.copyWith(notificationBodyPreview: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      AppSettingsController._notificationBodyPreviewKey,
      value,
    );
    if (broadcast) {
      try {
        await _broadcastSettingChange(
          'update_notification_body_preview',
          value,
        );
      } catch (e) {
        debugPrint('Failed to broadcast notification body preview change: $e');
      }
    }
  }

  Future<void> setHarmonyShareNotifications(
    bool value, {
    bool broadcast = true,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await _writeHarmonyPreference(
      preferences,
      () =>
          preferences.setBool(HarmonySharePreferenceKeys.notifications, value),
    );
    state = state.copyWith(harmonyShareNotifications: value);
    if (broadcast) {
      try {
        await _broadcastSettingChange(
          'update_harmony_share_notifications',
          value,
        );
      } catch (failure) {
        debugPrint('Harmony Share settings broadcast failed: $failure');
      }
    }
  }

  /// 目录只在用户明确选择时做写入探测；广播接收方不重复探测文件系统。
  Future<void> setHarmonyShareReceiveDirectory(
    String value, {
    bool broadcast = true,
    bool validate = true,
  }) async {
    ShareReceiveDirectory.validatePath(value);
    if (validate && value.isNotEmpty) {
      await ShareReceiveDirectory.checkWritable(
        value,
      ).timeout(const Duration(seconds: 15));
    }
    final preferences = await SharedPreferences.getInstance();
    await _writeHarmonyPreference(
      preferences,
      () => preferences.setString(
        HarmonySharePreferenceKeys.receiveDirectory,
        value,
      ),
    );
    state = state.copyWith(harmonyShareReceiveDirectory: value);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_harmony_share_directory', value);
      } catch (failure) {
        debugPrint('Harmony Share directory broadcast failed: $failure');
      }
    }
  }

  /// legacy SharedPreferences 在磁盘写入前更新缓存，失败时重读，避免服务使用未保存路径。
  Future<void> _writeHarmonyPreference(
    SharedPreferences preferences,
    Future<bool> Function() write,
  ) async {
    try {
      if (!await write()) throw StateError('Settings write failed');
    } catch (_) {
      try {
        await preferences.reload();
      } catch (failure) {
        debugPrint('Harmony Share preferences reload failed: $failure');
      }
      rethrow;
    }
  }
}
