part of 'app_settings_controller.dart';

/// 传输模式由主窗口校验空闲状态后保存；子窗口只请求变更并重读落盘值。
mixin HarmonyTransferSettings
    on
        Notifier<AppSettings>,
        SettingsBroadcast,
        NotificationSettings,
        HarmonyNameSettings {
  Future<void> setHarmonyShareDirectMode(
    bool value, {
    bool broadcast = true,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (!broadcast) {
      await _reloadHarmonyShareDirectMode(preferences);
      return;
    }
    if (ref.read(windowIdProvider).isNotEmpty) {
      await AppSettingsController._mainSettingsChannel.invokeMethod(
        'change_harmony_share_direct_mode',
        value,
      );
      await _reloadHarmonyShareDirectMode(preferences);
      return;
    }
    await HarmonyShareService.instance.configureDirectMode(value, () async {
      await _writeHarmonyPreference(
        preferences,
        () => preferences.setBool(HarmonySharePreferenceKeys.directMode, value),
      );
      state = state.copyWith(harmonyShareDirectMode: value);
    });
    try {
      await _broadcastSettingChange('update_harmony_share_direct_mode', value);
    } catch (failure) {
      debugPrint('Harmony Share transfer mode broadcast failed: $failure');
    }
  }

  /// 广播是重载信号，迟到的旧值不能覆盖已经保存的新模式。
  Future<void> _reloadHarmonyShareDirectMode(
    SharedPreferences preferences,
  ) async {
    await preferences.reload();
    state = state.copyWith(
      harmonyShareDirectMode:
          preferences.getBool(HarmonySharePreferenceKeys.directMode) ?? false,
    );
  }

  /// 鸿蒙互联设置共用主窗口请求入口，所有分支保留参数类型检查。
  Future<bool> _handleHarmonyShareSettingsCall(MethodCall call) async {
    if (call.method == 'change_harmony_share_direct_mode' &&
        call.arguments is bool) {
      await setHarmonyShareDirectMode(call.arguments as bool);
    } else if (call.method == 'update_harmony_share_direct_mode' &&
        call.arguments is bool) {
      await setHarmonyShareDirectMode(call.arguments as bool, broadcast: false);
    } else if (call.method == 'change_harmony_share_local_name' &&
        call.arguments is String) {
      await setHarmonyShareLocalName(call.arguments as String);
    } else if (call.method == 'update_harmony_share_local_name' &&
        call.arguments is String) {
      await setHarmonyShareLocalName(
        call.arguments as String,
        broadcast: false,
      );
    } else if (call.method == 'update_harmony_share_notifications' &&
        call.arguments is bool) {
      await setHarmonyShareNotifications(
        call.arguments as bool,
        broadcast: false,
      );
    } else if (call.method == 'update_harmony_share_directory' &&
        call.arguments is String) {
      await setHarmonyShareReceiveDirectory(
        call.arguments as String,
        broadcast: false,
        validate: false,
      );
    } else {
      return false;
    }
    return true;
  }
}
