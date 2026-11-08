import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings_controller.dart';
import '../shortcuts/keyboard_shortcut_binding.dart';
import '../shortcuts/local_shortcut_handler.dart';
import '../shortcuts/window_shortcut.dart';
import '../widget/app_toast.dart';
import 'window_shortcut_bridge.dart';

/// 独立窗口的可配置快捷键范围；关闭只影响当前窗口，设置和退出委托主窗口。
/// child 为窗口内容；投屏内层已有自动聚焦时，autofocus 应设为 false。
class WindowCloseShortcut extends ConsumerWidget {
  const WindowCloseShortcut({
    super.key,
    required this.child,
    this.autofocus = true,
  });
  final Widget child;
  final bool autofocus;

  Future<void> _perform(BuildContext context, WindowShortcut action) async {
    try {
      if (action == WindowShortcut.closeWindow) {
        await windowManager.close();
      } else {
        await WindowShortcutBridge.request(action);
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.show(
          context,
          context.l10n.t('shortcutActionFailed'),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      appSettingsProvider.select((s) => s.windowShortcuts),
    );
    return LocalShortcutHandler(
      autofocus: autofocus,
      includeScopeFocus: true,
      resolve: (event) {
        final action = settings.match(event);
        return action == null
            ? null
            : LocalShortcutMatch(() => _perform(context, action));
      },
      child: child,
    );
  }
}

/// 主窗口统一处理唤起、关闭、设置和退出，完整组合键在输入控件之前生效。
/// onOpenSettings 跳转设置页；onQuit 复用应用的二次退出确认与资源回收流程。
class MainWindowCloseShortcut extends ConsumerStatefulWidget {
  const MainWindowCloseShortcut({
    super.key,
    required this.child,
    this.showWindowKey = '1',
    this.showWindowShortcut,
    this.onQuit,
    this.onOpenSettings,
  });
  final Widget child;

  /// 兼容旧单字符调用；显式完整组合键优先，disabled 表示禁用唤起键。
  final String showWindowKey;
  final KeyboardShortcutBinding? showWindowShortcut;
  final VoidCallback? onQuit;
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<MainWindowCloseShortcut> createState() =>
      _MainWindowCloseShortcutState();
}

class _MainWindowCloseShortcutState
    extends ConsumerState<MainWindowCloseShortcut> {
  @override
  void initState() {
    super.initState();
    unawaited(
      WindowShortcutBridge.register(this, _handleRemote).catchError((
        Object error,
      ) {
        debugPrint('Failed to register window shortcut bridge: $error');
      }),
    );
  }

  @override
  void dispose() {
    unawaited(
      WindowShortcutBridge.unregister(this).catchError((Object error) {
        debugPrint('Failed to unregister window shortcut bridge: $error');
      }),
    );
    super.dispose();
  }

  Future<void> _handleRemote(WindowShortcut action) async {
    if (!mounted) return;
    await windowManager.show();
    await windowManager.focus();
    if (mounted) await _perform(action);
  }

  Future<void> _perform(WindowShortcut action) async {
    try {
      switch (action) {
        case WindowShortcut.closeWindow:
          await windowManager.close();
        case WindowShortcut.openSettings:
          widget.onOpenSettings?.call();
        case WindowShortcut.quitApp:
          if (widget.onQuit != null) {
            widget.onQuit!();
          } else {
            await windowManager.setPreventClose(false);
            await windowManager.destroy();
            exit(0);
          }
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          context.l10n.t('shortcutActionFailed'),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(
      appSettingsProvider.select((s) => s.windowShortcuts),
    );
    final legacyKey = normalizeMainWindowShortcut(widget.showWindowKey);
    final showBinding =
        widget.showWindowShortcut ??
        KeyboardShortcutBinding.primary(
          LogicalKeyboardKey(legacyKey.codeUnitAt(0)),
        );
    return LocalShortcutHandler(
      includeScopeFocus: true,
      resolve: (event) {
        final action = settings.match(event);
        if (action != null) return LocalShortcutMatch(() => _perform(action));
        return showBinding.matches(event)
            ? LocalShortcutMatch(() async {
                await windowManager.show();
                await windowManager.focus();
              })
            : null;
      },
      child: widget.child,
    );
  }
}
