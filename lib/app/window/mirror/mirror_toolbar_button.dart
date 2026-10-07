import 'package:flutter/material.dart';

/// 投屏工具栏公共按钮；icon/tooltip 描述操作，onPressed 为空时禁用。
/// 可选长按、指针回调和 badge 用于截图保存、按键长按及录制状态。
class MirrorToolbarButton extends StatefulWidget {
  const MirrorToolbarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isLoading = false,
    this.badge,
    this.onPointerDown,
    this.onPointerUp,
    this.onPointerCancel,
    this.onLongPress,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? badge;
  final VoidCallback? onPointerDown;
  final VoidCallback? onPointerUp;
  final VoidCallback? onPointerCancel;
  final VoidCallback? onLongPress;

  @override
  State<MirrorToolbarButton> createState() => _MirrorToolbarButtonState();
}

class _MirrorToolbarButtonState extends State<MirrorToolbarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hoverBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      margin: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedScale(
          scale: _isHovered ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: Listener(
            onPointerDown: (_) => widget.onPointerDown?.call(),
            onPointerUp: (_) => widget.onPointerUp?.call(),
            onPointerCancel: (_) => widget.onPointerCancel?.call(),
            child: Stack(
              alignment: Alignment.center,
              children: [
                GestureDetector(
                  onLongPress: widget.isLoading ? null : widget.onLongPress,
                  child: IconButton(
                    iconSize: 14,
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: _isHovered
                          ? hoverBg
                          : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: widget.isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : widget.icon,
                    onPressed: widget.isLoading ? null : widget.onPressed,
                  ),
                ),
                if (widget.badge != null)
                  Positioned(top: 2, right: 2, child: widget.badge!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 工具栏录屏中的脉冲提示，独立管理并释放动画控制器。
class MirrorPulsingRecordBadge extends StatefulWidget {
  const MirrorPulsingRecordBadge({super.key});

  @override
  State<MirrorPulsingRecordBadge> createState() =>
      _MirrorPulsingRecordBadgeState();
}

class _MirrorPulsingRecordBadgeState extends State<MirrorPulsingRecordBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.2).animate(_controller),
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// 工具栏分组间的预留分隔占位，沿用原有布局。
class MirrorToolbarDivider extends StatelessWidget {
  const MirrorToolbarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container();
    //分割线
    // final isDark = Theme.of(context).brightness == Brightness.dark;
    // return Container(
    //   width: 1,
    //   height: 16,
    //   margin: const EdgeInsets.symmetric(horizontal: 8),
    //   color: isDark ? Colors.white24 : Colors.black12,
    // );
  }
}
