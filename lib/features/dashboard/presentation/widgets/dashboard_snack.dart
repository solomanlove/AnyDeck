import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Dashboard 全局轻提示工具，统一各 Tab 的成功/错误反馈样式。
class DashboardSnack {
  const DashboardSnack._();

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    final media = MediaQuery.of(context);
    final accentColor = isError
        ? Theme.of(context).colorScheme.error
        : const Color(0xff00c853);
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: const Color(0xff171a21),
      fontWeight: FontWeight.w600,
    );

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: media.padding.top + 16,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: media.size.width - 64),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xffd7dce5)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isError
                              ? CupertinoIcons.exclamationmark_circle_fill
                              : CupertinoIcons.checkmark_circle_fill,
                          color: accentColor,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Flexible(child: Text(message, style: textStyle)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Timer(const Duration(seconds: 2), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }
}
