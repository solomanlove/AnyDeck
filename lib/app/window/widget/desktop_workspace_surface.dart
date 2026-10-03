import 'dart:ui';

import 'package:flutter/material.dart';

import '../model/desktop_chrome_policy.dart';

/// 工作区公共背景。[child] 为页面内容；[border] 用于导航与内容分隔。
/// macOS 延续通透材质，Windows/Linux 使用主题实色并省去模糊合成。
class DesktopWorkspaceSurface extends StatelessWidget {
  const DesktopWorkspaceSurface({super.key, required this.child, this.border});

  final Widget child;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mac = DesktopChromePolicy.current.usesMacChrome;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: mac
            ? (isDark
                  ? Colors.black.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.28))
            : theme.colorScheme.surface,
        border: border,
      ),
      // Material 必须位于装饰层上方，保证列表底色与 Ink 可见。
      child: Material(type: MaterialType.transparency, child: child),
    );
    if (!mac) return content;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: content,
      ),
    );
  }
}
