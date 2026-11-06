part of '../dashboard_screen.dart';

/// 退出快捷键的二次确认与动态提示，资源回收仍复用主窗口原有入口。
extension _DashboardQuitShortcut on _DashboardScreenState {
  void _handleQuitShortcut() {
    final now = DateTime.now();
    final lastPressedAt = _lastQuitShortcutAt;
    if (lastPressedAt != null &&
        now.difference(lastPressedAt) <=
            _DashboardScreenState._quitShortcutInterval) {
      _lastQuitShortcutAt = null;
      unawaited(_exitApp());
      return;
    }

    _lastQuitShortcutAt = now;
    if (mounted) {
      final shortcut = ref
          .read(appSettingsProvider)
          .windowShortcuts
          .bindingFor(WindowShortcut.quitApp)
          .label();
      _showSnack(
        context,
        context.l10n
            .t('pressShortcutAgainToQuit')
            .replaceAll('{shortcut}', shortcut),
      );
    }
  }
}
