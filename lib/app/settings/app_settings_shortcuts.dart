part of 'app_settings_controller.dart';

const mainWindowShortcutPreferenceKey = 'settings.mainWindowShortcut';
const mainWindowShortcutChannelMethod = 'update_main_window_shortcut';

/// 读取新格式的主窗口组合键，损坏时回退旧设置。
KeyboardShortcutBinding? decodeMainWindowShortcut(String? encoded) =>
    KeyboardShortcutBinding.decode(encoded);

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
  /// 源窗口在写入前检查所有重叠作用范围，接收端允许广播中的中间状态。
  void _validateShortcuts(
    AppSettings candidate, {
    WindowShortcut? windowAction,
    MirrorShortcut? mirrorAction,
  }) {
    final binding = windowAction != null
        ? candidate.windowShortcuts.bindingFor(windowAction)
        : mirrorAction != null
        ? candidate.mirrorShortcuts.bindingFor(mirrorAction)
        : candidate.mainWindowBinding;
    final conflict = candidate.shortcutConflict(
      binding,
      windowAction: windowAction,
      mirrorAction: mirrorAction,
    );
    if (conflict != null) throw ShortcutConflictException(conflict);
  }

  Future<void> _receiveWindowShortcuts(Object? encoded) async {
    if (encoded is String) {
      await setWindowShortcuts(
        WindowShortcutSettings.decode(encoded),
        broadcast: false,
      );
    }
  }

  Future<void> setWindowShortcuts(
    WindowShortcutSettings value, {
    bool broadcast = true,
  }) async {
    final candidate = state.copyWith(windowShortcuts: value);
    if (broadcast) {
      for (final action in WindowShortcut.values) {
        _validateShortcuts(candidate, windowAction: action);
      }
    }
    state = candidate;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      WindowShortcutSettings.preferenceKey,
      value.encode(),
    );
    if (ref.read(windowIdProvider).isEmpty) {
      await DesktopWindowManagerService.updateTrayMenu(state.language.code);
    }
    if (broadcast) {
      await _broadcastSettingChange(
        WindowShortcutSettings.channelMethod,
        value.encode(),
      );
    }
  }

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
        !KeyboardShortcutBinding.isTrigger(binding.key!))) {
      throw ArgumentError.value(binding, 'binding');
    }
    final candidate = state.copyWith(mainWindowShortcut: binding);
    if (broadcast) _validateShortcuts(candidate);
    state = candidate;
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
    final candidate = state.copyWith(mirrorShortcuts: value);
    if (broadcast) {
      for (final action in MirrorShortcut.values) {
        _validateShortcuts(candidate, mirrorAction: action);
      }
    }
    state = candidate;
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
