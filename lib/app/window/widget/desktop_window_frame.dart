import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_icon.dart';
import '../controller/desktop_caption_controller.dart';
import '../model/desktop_chrome_policy.dart';

/// 主窗口公共外壳。在 MaterialApp.builder 内包裹路由内容 [child]，
/// Windows 固定显示标题栏；macOS/Linux 的按钮由原生窗口负责。
/// [title] 必须传入本地化后的应用名，不在这里重复页面操作。
class DesktopWindowFrame extends StatelessWidget {
  const DesktopWindowFrame({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DesktopChromePolicy.current.usesCustomCaption) return child;
    // builder 位于路由 Navigator 外，单独提供 Overlay 以承载标题栏 Tooltip。
    return Overlay.wrap(
      child: Column(
        children: [
          _WindowsCaption(title: title),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 只重建标题栏，窗口聚焦与最大化事件不触发业务页面刷新。
class _WindowsCaption extends StatefulWidget {
  const _WindowsCaption({required this.title});
  final String title;

  @override
  State<_WindowsCaption> createState() => _WindowsCaptionState();
}

class _WindowsCaptionState extends State<_WindowsCaption> {
  late final DesktopCaptionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DesktopCaptionController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_controller.fullScreen) return const SizedBox.shrink();
        return Material(
          color: colors.surfaceContainerLow,
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Image.asset(AppIcons.appLogo, width: 18, height: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: _controller.focused
                                    ? colors.onSurface
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _CaptionButton(
                  label: context.l10n.t('windowMinimize'),
                  icon: Icons.remove,
                  onPressed: _controller.busy ? null : _controller.minimize,
                ),
                _CaptionButton(
                  label: context.l10n.t(
                    _controller.maximized ? 'windowRestore' : 'windowMaximize',
                  ),
                  icon: _controller.maximized
                      ? Icons.filter_none
                      : Icons.crop_square,
                  onPressed: _controller.busy
                      ? null
                      : _controller.toggleMaximized,
                ),
                _CaptionButton(
                  label: context.l10n.t('close'),
                  icon: Icons.close,
                  isClose: true,
                  onPressed: _controller.busy ? null : _controller.close,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 使用标准按钮获得键盘焦点、语义标签和 Tooltip，按钮不属于拖拽区。
class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    bool active(Set<WidgetState> states) =>
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.pressed);
    return Tooltip(
      message: label,
      child: SizedBox(
        width: 46,
        height: 36,
        child: TextButton(
          onPressed: onPressed,
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: const WidgetStatePropertyAll(Size.zero),
            shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  isClose && active(states) ? colors.onError : colors.onSurface,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  isClose && active(states) ? colors.error : Colors.transparent,
            ),
          ),
          child: Icon(icon, size: 16, semanticLabel: label),
        ),
      ),
    );
  }
}
