import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../model/android_version_distribution_data.dart';

/// Android 平台与 API 版本分布视图中的右侧特性详情面板。
/// 深度自适应主窗口的明暗主题与中英文语言切换。
class AndroidDistributionDetailsPane extends StatelessWidget {
  const AndroidDistributionDetailsPane({
    super.key,
    required this.item,
    required this.onOpenUrl,
  });

  /// 当前选中的版本条目
  final AndroidDistributionItem item;

  /// 打开官方文档链接回调
  final void Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langCode = Localizations.localeOf(context).languageCode;
    final sections = item.featureSections;

    final titleColor = isDark ? Colors.white : const Color(0xFF1F2328);
    final linkColor = isDark ? const Color(0xFF4DA3FF) : const Color(0xFF0969DA);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部版本代号大标题 (如 "B")
          Text(
            item.codename,
            style: TextStyle(
              color: titleColor,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          // 特性列表或预留空态
          Expanded(
            child: sections.isEmpty
                ? _buildEmptySectionsPlaceholder(context, isDark)
                : SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final hasExplicitColumns = sections.any((s) => s.columnIndex != null);
                        final List<AndroidFeatureSection> leftCols;
                        final List<AndroidFeatureSection> rightCols;

                        if (hasExplicitColumns) {
                          leftCols = sections.where((s) => s.columnIndex != 1).toList();
                          rightCols = sections.where((s) => s.columnIndex == 1).toList();
                        } else {
                          final half = (sections.length / 2).ceil();
                          leftCols = sections.take(half).toList();
                          rightCols = sections.skip(half).toList();
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: leftCols
                                    .map((s) => _buildSectionWidget(s, isDark, langCode))
                                    .toList(),
                              ),
                            ),
                            if (rightCols.isNotEmpty) ...[
                              const SizedBox(width: 24),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: rightCols
                                      .map((s) => _buildSectionWidget(s, isDark, langCode))
                                      .toList(),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
          ),
          // 底部官方文档链接
          if (item.summaryUrl != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => onOpenUrl(item.summaryUrl!),
              child: Text(
                item.summaryUrl!,
                style: TextStyle(
                  color: linkColor,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 单个特性分类渲染（支持明暗模式与中英本地化）
  Widget _buildSectionWidget(
    AndroidFeatureSection section,
    bool isDark,
    String langCode,
  ) {
    final headerColor = isDark ? Colors.white : const Color(0xFF1F2328);
    final itemColor =
        isDark ? Colors.white.withValues(alpha: 0.82) : const Color(0xFF32383F);
    final bulletColor =
        isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF8C959F);

    final title = section.localizedTitle(langCode);
    final items = section.localizedItems(langCode);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: headerColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          ...items.map(
            (subItem) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•  ',
                    style: TextStyle(
                      color: bulletColor,
                      fontSize: 12,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      subItem,
                      style: TextStyle(
                        color: itemColor,
                        fontSize: 12,
                        height: 1.35,
                      ),
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

  /// 暂无特性数据时的预留占位提示
  Widget _buildEmptySectionsPlaceholder(BuildContext context, bool isDark) {
    final iconColor =
        isDark ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.25);
    final titleColor =
        isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF57606A);
    final hintColor =
        isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF8C959F);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.article_outlined,
            size: 40,
            color: iconColor,
          ),
          const SizedBox(height: 12),
          Text(
            'Android ${item.platformVersion} (API ${item.apiLevel})',
            style: TextStyle(
              color: titleColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.t('versionDistributionPlaceholderDesc'),
            style: TextStyle(
              color: hintColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
