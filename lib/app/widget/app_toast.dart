import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// App 全局居中 Toast，统一主窗口与独立子窗口的轻提示样式。
class AppToast {
  const AppToast._();

  static OverlayEntry? _currentEntry;
  static Timer? _hideTimer;

  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.success,
    bool? isError,
    Duration duration = const Duration(milliseconds: 1600),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null || message.isEmpty) {
      return;
    }

    final resolvedType = isError == null
        ? type
        : (isError ? AppToastType.error : AppToastType.success);
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final style = _AppToastStyle.resolve(theme, resolvedType, isDark);

    _hideCurrent();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: IgnorePointer(
            child: SafeArea(
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: media.size.width < 420
                        ? media.size.width - 48
                        : 420,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: style.backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: style.borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.42 : 0.18,
                          ),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(style.icon, color: style.iconColor, size: 22),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: style.textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _currentEntry = entry;
    overlay.insert(entry);
    _hideTimer = Timer(duration, _hideCurrent);
  }

  static void _hideCurrent() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_currentEntry?.mounted ?? false) {
      _currentEntry?.remove();
    }
    _currentEntry = null;
  }
}

enum AppToastType { success, error, warning, info }

class _AppToastStyle {
  const _AppToastStyle({
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.iconColor,
    required this.icon,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final Color iconColor;
  final IconData icon;

  static _AppToastStyle resolve(
    ThemeData theme,
    AppToastType type,
    bool isDark,
  ) {
    final colorScheme = theme.colorScheme;
    final backgroundColor = isDark
        ? const Color(0xff20242b)
        : const Color(0xffffffff);
    final borderColor = isDark
        ? const Color(0xff3a404a)
        : const Color(0xffd7dce5);
    final textColor = isDark
        ? const Color(0xfff4f6fb)
        : const Color(0xff171a21);

    return switch (type) {
      AppToastType.success => _AppToastStyle(
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        textColor: textColor,
        iconColor: const Color(0xff00c853),
        icon: CupertinoIcons.checkmark_circle_fill,
      ),
      AppToastType.error => _AppToastStyle(
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        textColor: textColor,
        iconColor: colorScheme.error,
        icon: CupertinoIcons.exclamationmark_circle_fill,
      ),
      AppToastType.warning => _AppToastStyle(
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        textColor: textColor,
        iconColor: const Color(0xfff29900),
        icon: CupertinoIcons.exclamationmark_triangle_fill,
      ),
      AppToastType.info => _AppToastStyle(
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        textColor: textColor,
        iconColor: colorScheme.primary,
        icon: CupertinoIcons.info_circle_fill,
      ),
    };
  }
}
