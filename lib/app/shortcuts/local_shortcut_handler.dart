import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 已匹配的本地操作；callback 为空表示按钮禁用，但仍消费对应按键。
class LocalShortcutMatch {
  const LocalShortcutMatch(this.callback);
  final VoidCallback? callback;
}

/// 在当前 Route 的焦点范围内优先处理本地快捷键，防止按键泄漏到设备。
/// resolve 返回 null 时沿用后续输入链路，child 不需要知道具体操作配置。
class LocalShortcutHandler extends StatefulWidget {
  const LocalShortcutHandler({
    super.key,
    required this.resolve,
    required this.child,
  });
  final LocalShortcutMatch? Function(KeyEvent event) resolve;
  final Widget child;

  @override
  State<LocalShortcutHandler> createState() => _LocalShortcutHandlerState();
}

class _LocalShortcutHandlerState extends State<LocalShortcutHandler> {
  final _focus = FocusNode(debugLabel: 'local_shortcuts');
  final _pressed = <LogicalKeyboardKey>{};

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
  }

  KeyEventResult _handleKey(KeyEvent event) {
    // 修饰键先松开、配置改变或打开弹窗时，也消费已处理触发键的 repeat/up。
    if (event is KeyUpEvent && _pressed.remove(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    if (_pressed.contains(event.logicalKey)) return KeyEventResult.handled;
    if (!_focus.hasFocus || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return KeyEventResult.ignored;
    }
    final match = widget.resolve(event);
    if (match == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _pressed.add(event.logicalKey);
      if (!event.synthesized) match.callback?.call();
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, focusNode: _focus, child: widget.child);
}
