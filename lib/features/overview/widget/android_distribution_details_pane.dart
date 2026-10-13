import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../model/android_version_distribution_data.dart';

/// Android 平台与 API 版本分布视图中的右侧特性详情面板。
/// 包含稳定版发布时间、开发影响与适配要求重点卡片以及全量新特性列表。
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

    final linkColor = isDark ? const Color(0xFF4DA3FF) : const Color(0xFF0969DA);

    // 区分“开发影响与适配要求”和其他常规特性分类
    final impactSection = sections.cast<AndroidFeatureSection?>().firstWhere(
          (s) => _isDeveloperImpactSection(s!),
          orElse: () => null,
        );
    final regularSections = sections
        .where((s) => !_isDeveloperImpactSection(s))
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 顶部版本大标题与元信息徽章栏（包含稳定版上线时间）
          _buildHeaderMetadata(context, isDark, langCode),
          const SizedBox(height: 14),
          // 2. 特性列表或预留空态
          Expanded(
            child: sections.isEmpty
                ? _buildEmptySectionsPlaceholder(context, isDark)
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 2.1 若存在“开发影响与适配要求”，置顶以高亮卡片呈现
                        if (impactSection != null) ...[
                          _buildDeveloperImpactCard(
                            impactSection,
                            isDark,
                            langCode,
                          ),
                          const SizedBox(height: 16),
                        ],
                        // 2.2 普通特性排版（确保靠左对齐与多列均衡）
                        if (regularSections.isNotEmpty)
                          _buildRegularSectionsLayout(
                            regularSections,
                            isDark,
                            langCode,
                          ),
                      ],
                    ),
                  ),
          ),
          // 3. 底部官方文档链接
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

  /// 判断分类是否为“开发影响与适配要求”
  bool _isDeveloperImpactSection(AndroidFeatureSection section) {
    final titleEn = section.title.toLowerCase();
    final titleZh = section.titleZh ?? '';
    return titleEn.contains('developer impact') ||
        titleZh.contains('开发影响') ||
        titleEn.contains('behavior changes') && !titleEn.contains('new features');
  }

  /// 构建顶部版本代号大标题、API 级别以及稳定版上线时间
  Widget _buildHeaderMetadata(
    BuildContext context,
    bool isDark,
    String langCode,
  ) {
    final titleColor = isDark ? Colors.white : const Color(0xFF1F2328);
    final subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF57606A);
    final badgeBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final badgeBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.1);
    final releaseDateText = item.localizedReleaseDate(langCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // 大号代号
            Text(
              item.codename,
              style: TextStyle(
                color: titleColor,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 14),
            // Android 版本与 API 级别胶囊
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: badgeBorder, width: 0.8),
              ),
              child: Text(
                'Android ${item.platformVersion}  •  API ${item.apiLevel}',
                style: TextStyle(
                  color: titleColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (item.cumulativeDistributionText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: badgeBorder, width: 0.8),
                ),
                child: Text(
                  '${context.l10n.t('cumulativeDistributionHeader').replaceAll('\n', ' ')}: ${item.cumulativeDistributionText}',
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
        // 稳定版发布时间信息行
        if (releaseDateText.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.event_available_outlined,
                size: 14,
                color: subtitleColor,
              ),
              const SizedBox(width: 5),
              Text(
                '${context.l10n.t('stableReleaseDatePrefix')}$releaseDateText',
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 构建开发影响与适配要求高亮强调卡片
  Widget _buildDeveloperImpactCard(
    AndroidFeatureSection section,
    bool isDark,
    String langCode,
  ) {
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

  /// 构建常规特性的排版布局（确保严格靠左对齐，并在多列时均匀分布）
  Widget _buildRegularSectionsLayout(
    List<AndroidFeatureSection> sections,
    bool isDark,
    String langCode,
  ) {
    // 只有 1 个常规分类时，直接排在左半边，绝不置空左列
    if (sections.length == 1) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildSectionWidget(sections.first, isDark, langCode),
          ),
          const SizedBox(width: 24),
          const Expanded(child: SizedBox.shrink()),
        ],
      );
    }

    final hasExplicitColumns = sections.any((s) => s.columnIndex != null);
    List<AndroidFeatureSection> leftCols;
    List<AndroidFeatureSection> rightCols;

    if (hasExplicitColumns) {
      leftCols = sections.where((s) => s.columnIndex != 1).toList();
      rightCols = sections.where((s) => s.columnIndex == 1).toList();
      // 防御式设计：若左列意外为空，自动将右列内容收口至左列
      if (leftCols.isEmpty) {
        final half = (sections.length / 2).ceil();
        leftCols = sections.take(half).toList();
        rightCols = sections.skip(half).toList();
      }
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
  }

  /// 单个常规特性分类渲染（支持明暗模式与中英本地化）
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
                    child: _buildFormattedItemText(
                      text: subItem,
                      itemColor: itemColor,
                      isDark: isDark,
                      height: 1.35,
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
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.25);
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
