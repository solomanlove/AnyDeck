part of 'app_settings_controller.dart';

const mainWindowShortcutPreferenceKey = 'settings.mainWindowShortcut';
const mainWindowShortcutChannelMethod = 'update_main_window_shortcut';

/// 读取新格式的主窗口组合键，损坏或占用固定操作的配置回退旧设置。
KeyboardShortcutBinding? decodeMainWindowShortcut(String? encoded) {
  final binding = KeyboardShortcutBinding.decode(encoded);
  return binding?.reservedLabelKey == null ? binding : null;
}

/// 与主窗口现有键码映射一致，旧的无效存储值回退到默认按键。
const mainWindowShortcutKeys = [
  '1',
  '2',
  '3',
  '4',
  '5',
  'a',
  'b',
  'd',
  'e',
  'm',
];

String normalizeMainWindowShortcut(String? key) {
  final clean = key?.trim().toLowerCase();
  return mainWindowShortcutKeys.contains(clean) ? clean! : '1';
}

/// 统一持久化和广播快捷键，已打开的投屏窗口立即更新。
mixin ShortcutSettings on Notifier<AppSettings>, SettingsBroadcast {
  Future<void> _receiveMainWindowShortcut(Object? encoded) async {
    if (encoded is! String) return;
    final binding = decodeMainWindowShortcut(encoded);
    if (binding != null) await setMainWindowShortcut(binding, broadcast: false);
  }

  Future<void> setMainWindowShortcut(
    KeyboardShortcutBinding binding, {
    bool broadcast = true,
  }) async {
    if ((binding.key != null &&
            !KeyboardShortcutBinding.isTrigger(binding.key!)) ||
        binding.reservedLabelKey != null) {
      throw ArgumentError.value(binding, 'binding');
    }
    state = state.copyWith(mainWindowShortcut: binding);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      mainWindowShortcutPreferenceKey,
      binding.encode(),
    );
    if (broadcast) {
      await _broadcastSettingChange(
        mainWindowShortcutChannelMethod,
        binding.encode(),
      );
    }
  }

  Future<void> _receiveMirrorShortcuts(Object? encoded) async {
    if (encoded is String) {
      await setMirrorShortcuts(
        MirrorShortcutSettings.decode(encoded),
        broadcast: false,
      );
    }
  }

  Future<void> setMirrorShortcuts(
    MirrorShortcutSettings value, {
    bool broadcast = true,
  }) async {
    state = state.copyWith(mirrorShortcuts: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      MirrorShortcutSettings.preferenceKey,
      value.encode(),
    );
    if (broadcast) {
      await _broadcastSettingChange(
        MirrorShortcutSettings.channelMethod,
        value.encode(),
      );
    }
  }

  /// 保留已有主窗口按键配置，并校验为当前支持的字符。
  Future<void> setShowWindowShortcut(String key) async {
    final clean = key.trim().toLowerCase();
    if (!mainWindowShortcutKeys.contains(clean)) {
      return;
    }
    state = state.copyWith(showWindowShortcutKey: clean);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      AppSettingsController._showWindowShortcutKey,
      clean,
    );
    await setMainWindowShortcut(
      KeyboardShortcutBinding.primary(LogicalKeyboardKey(clean.codeUnitAt(0))),
    );
  }
}
