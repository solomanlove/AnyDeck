import 'package:flutter/material.dart';

import 'in_app_webview_widget.dart';

/// 桌面端内嵌 WebView 弹窗容器。
/// 用于在应用内快速预览、加载或调试特定的 Web 链接。
class InAppWebViewDialog extends StatelessWidget {
  final String url;
  final String? title;
  final double width;
  final double height;

  const InAppWebViewDialog({
    super.key,
    required this.url,
    this.title,
    this.width = 960,
    this.height = 680,
  });

  /// 快捷弹出 WebView 弹窗的辅助方法。
  static Future<void> show(
    BuildContext context, {
    required String url,
    String? title,
    double width = 960,
    double height = 680,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => InAppWebViewDialog(
        url: url,
        title: title,
        width: width,
        height: height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width * 0.85).clamp(480.0, width);
    final dialogHeight = (screenSize.height * 0.85).clamp(360.0, height);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: InAppWebViewWidget(
          initialUrl: url,
          title: title,
          showToolbar: true,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
