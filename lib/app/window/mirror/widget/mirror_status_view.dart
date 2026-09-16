import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widget/app_toast.dart';
import '../model/mirror_error_info.dart';

/// 投屏独立窗口状态展示组件。
///
/// 用于集中承接投屏过程中的“启动失败/异常报错/设备离线断开”以及“未连接/投屏已停止”等非活跃状态的友好界面呈现。
/// 支持智能根据错误类型展示专用图标、友好标题与排障提示文案，并提供可展开的原始技术细节和复制功能。
///
/// 用法示例：
/// ```dart
/// MirrorStatusView(
///   rawErrorMessage: _controller.errorMessage,
///   isStoppedState: !isMirrorActive,
///   onRetry: _controller.restartMirroring,
/// )
/// ```
class MirrorStatusView extends StatefulWidget {
  const MirrorStatusView({
    super.key,
    this.rawErrorMessage,
    this.isStoppedState = false,
    required this.onRetry,
  });

  /// 底层启动抛出的原始错误信息（若有）
  final String? rawErrorMessage;

  /// 是否为投屏停止/未连接状态
  final bool isStoppedState;

  /// 点击重试按钮的回调函数
  final VoidCallback onRetry;

  @override
  State<MirrorStatusView> createState() => _MirrorStatusViewState();
}

class _MirrorStatusViewState extends State<MirrorStatusView> {
  /// 是否展开展示底层原始错误堆栈详情
  bool _isDetailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    // 解析结构化错误数据
    final errorInfo = MirrorErrorInfo.fromRawError(widget.rawErrorMessage);

    // 计算标题文案与样式
    final String titleText;
    final String descriptionText;
    final IconData statusIcon;
    final Color iconColor;

    if (widget.rawErrorMessage != null && widget.rawErrorMessage!.isNotEmpty) {
      titleText = context.l10n.t(errorInfo.titleKey);
      if (errorInfo.type == MirrorErrorType.general &&
          errorInfo.fallbackDescription != null) {
        descriptionText = errorInfo.fallbackDescription!;
      } else {
        descriptionText = context.l10n.t(errorInfo.descriptionKey);
      }

      if (errorInfo.isOffline) {
        statusIcon = Icons.phonelink_erase_rounded;
        iconColor = Colors.orangeAccent;
      } else {
        statusIcon = errorInfo.icon;
        iconColor = Colors.redAccent;
      }
    } else {
      // 投屏停止状态
      titleText = context.l10n.t('mirrorStopped');
      descriptionText = context.l10n.t('deviceOfflineHint');
      statusIcon = Icons.portable_wifi_off_rounded;
      iconColor = isDark ? Colors.white54 : Colors.black45;
    }

    final hasRawError = widget.rawErrorMessage != null &&
        widget.rawErrorMessage!.trim().isNotEmpty &&
        errorInfo.type != MirrorErrorType.general;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 状态图标
            Icon(statusIcon, color: iconColor, size: 52),
            const SizedBox(height: 16),

            // 主标题
            Text(
              titleText,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 10),

            // 友好副文本 / 提示文案
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                descriptionText,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54,
                  height: 1.4,
                ),
              ),
            ),

            // 底层原始技术详情（可折叠查看，方便开发/排查）
            if (hasRawError) ...[
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  setState(() {
                    _isDetailsExpanded = !_isDetailsExpanded;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isDetailsExpanded
                            ? context.l10n.t('hideErrorDetails')
                            : context.l10n.t('viewErrorDetails'),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _isDetailsExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 14,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ],
                  ),
                ),
              ),
              if (_isDetailsExpanded) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xff1e1e1e)
                        : const Color(0xfff0f1f3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xff333333)
                          : const Color(0xffe0e0e0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SelectableText(
                        widget.rawErrorMessage!,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.copy, size: 12),
                          label: Text(
                            context.l10n.t('copyErrorDetails'),
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: widget.rawErrorMessage!),
                            );
                            AppToast.show(
                              context,
                              context.l10n.t('errorDetailsCopied'),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            const SizedBox(height: 24),

            // 重试按钮
            ElevatedButton.icon(
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(context.l10n.t('retry')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
