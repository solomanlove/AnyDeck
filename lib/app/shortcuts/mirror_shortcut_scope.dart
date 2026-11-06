import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings_controller.dart';
import 'mirror_shortcut.dart';

/// 在投屏窗口内优先处理本地组合键；child 为窗口内容。
/// 工具栏通过 MirrorShortcutTarget 注册同一份点击回调，自动隐藏后仍可使用。
class MirrorShortcutScope extends ConsumerStatefulWidget {
  const MirrorShortcutScope({super.key, required this.child, this.onClose});

  final Widget child;

  /// 标准窗口关闭入口，优先于设备键盘转发执行。
  final VoidCallback? onClose;

  static MirrorShortcutRegistry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShortcutScope>()?.registry;

  @override
  ConsumerState<MirrorShortcutScope> createState() =>
      _MirrorShortcutScopeState();
}

class _MirrorShortcutScopeState extends ConsumerState<MirrorShortcutScope> {
  final _focus = FocusNode(debugLabel: 'mirror_shortcuts');
  final _registry = MirrorShortcutRegistry();
  final _pressed = <LogicalKeyboardKey>{};

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
  }

  KeyEventResult _handleKey(KeyEvent event) {
    // 即使修饰键先抬起或操作打开弹窗，也吞掉已消费按键的 repeat/up。
    if (event is KeyUpEvent && _pressed.remove(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    if (_pressed.contains(event.logicalKey)) return KeyEventResult.handled;
    if (!_focus.hasFocus || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return KeyEventResult.ignored;
    }
    final closeWindow =
        widget.onClose != null &&
        SingleActivator(
          LogicalKeyboardKey.keyW,
          meta: _registry.isMacOS,
          control: !_registry.isMacOS,
          includeRepeats: false,
        ).accepts(event, HardwareKeyboard.instance);
    final action = _registry.settings.match(event, isMacOS: _registry.isMacOS);
    if (!closeWindow && action == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _pressed.add(event.logicalKey);
      if (!event.synthesized) {
        if (closeWindow) {
          widget.onClose!();
        } else {
          _registry.invoke(action!);
        }
      }
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    _focus.dispose();
    _registry.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(
      appSettingsProvider.select((s) => s.mirrorShortcuts),
    );
    _registry.settings = settings;
    _registry.isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    return _ShortcutScope(
      registry: _registry,
      settings: settings,
      child: Focus(autofocus: true, focusNode: _focus, child: widget.child),
    );
  }
}

class _ShortcutScope extends InheritedWidget {
  const _ShortcutScope({
    required this.registry,
    required this.settings,
    required super.child,
  });

  final MirrorShortcutRegistry registry;
  final MirrorShortcutSettings settings;

  @override
  bool updateShouldNotify(_ShortcutScope oldWidget) =>
      settings != oldWidget.settings;
}

/// 当前窗口的操作回调表；禁用、卸载和平台隐藏均与按钮保持一致。
class MirrorShortcutRegistry {
  MirrorShortcutSettings settings = const MirrorShortcutSettings();
  bool isMacOS = false;
  final _targets = <Object, Map<MirrorShortcut, VoidCallback?>>{};

  void register(Object owner, Map<MirrorShortcut, VoidCallback?> callbacks) =>
      _targets[owner] = callbacks;
  void unregister(Object owner) => _targets.remove(owner);
  void clear() => _targets.clear();

  void invoke(MirrorShortcut action) {
    for (final callbacks in _targets.values) {
      if (callbacks.containsKey(action)) {
        callbacks[action]?.call();
        return;
      }
    }
  }

  String label(MirrorShortcut action) =>
      settings.label(action, isMacOS: isMacOS);

  /// 按当前配置补充 Tooltip，禁用绑定时仅保留操作说明。
  String tooltip(MirrorShortcut? action, String description) {
    final key = action == null ? '' : label(action);
    return key.isEmpty ? description : '$description ($key)';
  }
}

/// 将按钮的当前回调绑定到所在窗口，更新和销毁时同步解绑。
/// callbacks 的 null 值表示该操作暂不可用，child 保留原有按钮 UI。
class MirrorShortcutTarget extends StatefulWidget {
  const MirrorShortcutTarget({
    super.key,
    required this.callbacks,
    required this.child,
  });

  final Map<MirrorShortcut, VoidCallback?> callbacks;
  final Widget child;

  @override
  State<MirrorShortcutTarget> createState() => _MirrorShortcutTargetState();
}

class _MirrorShortcutTargetState extends State<MirrorShortcutTarget> {
  MirrorShortcutRegistry? _registry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registry?.unregister(this);
    _registry = MirrorShortcutScope.maybeOf(context);
    _registry?.register(this, widget.callbacks);
  }

  @override
  void didUpdateWidget(covariant MirrorShortcutTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _registry?.register(this, widget.callbacks);
  }

  @override
  void dispose() {
    _registry?.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
