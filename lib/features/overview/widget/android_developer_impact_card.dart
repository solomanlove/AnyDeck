import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/l10n/app_localizations.dart';
import '../model/android_version_distribution_data.dart';

/// Android 平台与 API 版本分布视图中的「开发影响与适配要求」高亮卡片组件。
///
/// 包含醒目闪电图标、加粗分类标题、支持一键复制整卡适配要求条目的操作按钮，
/// 以及智能加粗小标题的特性条目清单。
class AndroidDeveloperImpactCard extends StatelessWidget {
  /// 构造函数
  const AndroidDeveloperImpactCard({
    super.key,
    required this.section,
    required this.platformVersion,
    required this.isDark,
    required this.langCode,
  });

  /// 开发影响与适配要求分类数据
  final AndroidFeatureSection section;

  /// Android 版本号 (如 '12', '16')，用于复制文案标题
  final String platformVersion;

  /// 是否为暗色模式
  final bool isDark;

  /// 当前语言代码
  final String langCode;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark
        ? const Color(0xFF2C281F)
        : const Color(0xFFFFF9E6);
    final cardBorder = isDark
        ? const Color(0xFFB08800).withValues(alpha: 0.45)
        : const Color(0xFFF1C40F).withValues(alpha: 0.6);
    final headerColor = isDark
        ? const Color(0xFFFFD54F)
        : const Color(0xFFB7791F);
    final itemColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : const Color(0xFF2D3748);
    final bulletColor = isDark
        ? const Color(0xFFFFD54F).withValues(alpha: 0.8)
        : const Color(0xFFD69E2E);

    final title = section.localizedTitle(langCode);
    final items = section.localizedItems(langCode);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorder, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                size: 16,
                color: headerColor,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: headerColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: headerColor,
                ),
                tooltip: '复制适配要求',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  final buffer = StringBuffer();
                  buffer.writeln('【Android $platformVersion $title】');
                  for (final item in items) {
                    buffer.writeln('• $item');
                  }
                  Clipboard.setData(
                    ClipboardData(text: buffer.toString().trim()),
                  );
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.t('copySuccess')),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (subItem) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•  ',
                    style: TextStyle(
                      color: bulletColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: _buildFormattedItemText(
                      text: subItem,
                      itemColor: itemColor,
                      isDark: isDark,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化单行特性条目：若包含冒号，将冒号前的小标题加粗强调
  Widget _buildFormattedItemText({
    required String text,
    required Color itemColor,
    required bool isDark,
    double height = 1.35,
  }) {
    // 匹配中文全角冒号 '：' 或英文冒号加空格 ': '
    final colonZhIndex = text.indexOf('：');
    final colonEnIndex = text.indexOf(': ');
    int colonIndex = -1;
    int colonLength = 1;

    if (colonZhIndex != -1 && (colonEnIndex == -1 || colonZhIndex < colonEnIndex)) {
      colonIndex = colonZhIndex;
      colonLength = 1;
    } else if (colonEnIndex != -1) {
      colonIndex = colonEnIndex;
      colonLength = 2;
    }

    // 仅在冒号位置合理（前 40 字符以内为标题）时执行加粗分割
    if (colonIndex != -1 && colonIndex <= 40) {
      final titlePart = text.substring(0, colonIndex);
      final colonChar = text.substring(colonIndex, colonIndex + colonLength);
      final bodyPart = text.substring(colonIndex + colonLength);
      final titleColor = isDark ? Colors.white : const Color(0xFF1F2328);

      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$titlePart$colonChar',
              style: TextStyle(
                color: titleColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: bodyPart,
              style: TextStyle(
                color: itemColor,
                fontWeight: FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
        style: TextStyle(
          height: height,
        ),
      );
    }

    return Text(
      text,
      style: TextStyle(
        color: itemColor,
        fontSize: 12,
        height: height,
      ),
    );
  }
}
