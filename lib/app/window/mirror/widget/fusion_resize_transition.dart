import 'dart:ui';

import 'package:flutter/material.dart';

/// 融合副屏重排期间模糊旧画面并阻止误触。
///
/// [resizing] 表示正在等待新尺寸的视频帧；[child] 是持续运行的投屏 Viewer。
/// 用法：在融合投屏的 Viewer 外包裹此组件，尺寸更新完成后传入 false。
class FusionResizeTransition extends StatelessWidget {
  const FusionResizeTransition({
    super.key,
    required this.resizing,
    required this.child,
  });

  final bool resizing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: resizing ? 18 : 0),
          duration: const Duration(milliseconds: 180),
          builder: (context, blur, child) => ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: child,
          ),
          child: child,
        ),
        IgnorePointer(
          ignoring: !resizing,
          child: AnimatedOpacity(
            opacity: resizing ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: ColoredBox(
              color: isDark ? Colors.black26 : Colors.white24,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black54 : Colors.white70,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Icon(
                      Icons.grid_view_rounded,
                      size: 26,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
