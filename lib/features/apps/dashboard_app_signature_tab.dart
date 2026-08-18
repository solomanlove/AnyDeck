part of '../dashboard_screen.dart';

/// 一个展示 Android 应用签名 MD5 值的 Tab 页面。
///
/// 包含标准冒号分隔格式以及原始小写格式的 MD5 签名，并提供便捷的复制按钮。
class _SignatureTab extends StatelessWidget {
  const _SignatureTab({required this.signatureMd5});

  /// 证书的 MD5 签名哈希值（32 位 16 进制字符串）。
  final String signatureMd5;

  @override
  Widget build(BuildContext context) {
    if (signatureMd5.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.info, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              context.l10n.t('noSignatureInfo'),
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // 格式化签名哈希值：转大写并在每两位字符间添加冒号
    String formatSignature(String raw) {
      if (raw.length != 32) return raw;
      final buffer = StringBuffer();
      for (int i = 0; i < raw.length; i += 2) {
        buffer.write(raw.substring(i, i + 2).toUpperCase());
        if (i < raw.length - 2) {
          buffer.write(':');
        }
      }
      return buffer.toString();
    }

    final formattedMd5 = formatSignature(signatureMd5);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color cardBg = isDark
        ? Colors.white.withValues(alpha: 0.02)
        : Colors.black.withValues(alpha: 0.01);

    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标准格式 MD5 证书卡片
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.t('signatureMd5'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: formattedMd5));
                          _showSnack(
                            context,
                            context.l10n.t('copySignatureSuccess'),
                          );
                        },
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(28),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    formattedMd5,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 原始格式 MD5 证书卡片
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.t('signatureMd5Raw'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: signatureMd5));
                          _showSnack(
                            context,
                            context.l10n.t('copySignatureSuccess'),
                          );
                        },
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(28),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    signatureMd5,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 签名说明提示区域
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.2,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.info_circle,
                        size: 16,
                        color: theme.colorScheme.primary.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.t('signatureHelpTitle'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.t('signatureHelpContent'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.5,
                      color: theme.textTheme.bodySmall?.color?.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
