import 'package:flutter/material.dart';

import '../model/harmony_version_distribution_data.dart';
import 'harmony_profile_config_card.dart';

/// HarmonyOS 平台版本特性与工程配置详情面板。
///
/// 包含双编号徽章 Hero、元数据胶囊标签群、开发影响与适配要求、
/// 可直接复制的 build-profile.json5 工程配置建议，以及平台核心与安全能力。
class HarmonyDistributionDetailsPane extends StatelessWidget {
  /// 构造函数
  const HarmonyDistributionDetailsPane({
    super.key,
    required this.item,
    required this.onOpenUrl,
  });

  /// 当前选中的鸿蒙版本明细项
  final HarmonyDistributionItem item;

  /// 打开外部链接的回调
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardBg = isDark ? const Color(0xFF282B30) : Colors.white;
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final textPrimary = isDark ? Colors.white : const Color(0xFF1F2328);
    final textSecondary = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xFF57606A);
    final brandRed = const Color(0xFFE84335);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 顶部 Hero：红底双层 Badge + 标题 + 元数据 Chips
          _buildHeroHeader(textPrimary, textSecondary, brandRed),
          const SizedBox(height: 16),

          // 2. 开发影响与适配要求卡片
          _buildImpactsCard(cardBg, cardBorder, textPrimary, textSecondary),
          const SizedBox(height: 16),

          // 3. 左右分栏：工程配置建议（带代码块） + 核心与安全能力
          _buildSplitSection(
            context,
            cardBg,
            cardBorder,
            textPrimary,
            textSecondary,
          ),
          const SizedBox(height: 14),

          // 4. 底部开发者联盟文档链接
          _buildDocLink(context),
        ],
      ),
    );
  }

  /// 构建顶部 Hero 区域
  Widget _buildHeroHeader(
    Color textPrimary,
    Color textSecondary,
    Color brandRed,
  ) {
    final isLatest = item.muteFlag == 'NEW';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 双层红底徽章
        Container(
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: brandRed,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: brandRed.withValues(alpha: 0.28),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.version,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'API ${item.api}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        // 标题与 Chip 群
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HarmonyOS ${item.version}${isLatest ? '（当前最新）' : ''}',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildChip('API 版本', item.api, isHighlight: true),
                  _buildChip('存量占比', item.share, isHighlight: true),
                  _buildChip('累计覆盖', item.cover),
                  _buildChip('发布时间', item.release),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 胶囊标签
  Widget _buildChip(String label, String value, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isHighlight
            ? const Color(0xFFE84335).withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: RichText(
        text: TextSpan(
          text: '$label ',
          style: TextStyle(
            fontSize: 11,
            color: isHighlight
                ? const Color(0xFFD93025)
                : const Color(0xFF5F6368),
          ),
          children: [
            TextSpan(
              text: value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isHighlight
                    ? const Color(0xFFD93025)
                    : const Color(0xFF202124),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 开发影响与适配要求卡片
  Widget _buildImpactsCard(
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text(
                '◆ 开发影响与适配要求',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE84335),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...item.impacts.map(
            (impact) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(fontSize: 13, height: 1.4)),
                  Expanded(
                    child: _buildRichImpactText(impact, textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 智能渲染带有小标题加粗的文本
  Widget _buildRichImpactText(String text, Color textColor) {
    final colonIdx = text.indexOf('：');
    if (colonIdx > 0 && colonIdx < 30) {
      final title = text.substring(0, colonIdx + 1);
      final body = text.substring(colonIdx + 1);
      return RichText(
        text: TextSpan(
          text: title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: textColor,
            height: 1.4,
          ),
          children: [
            TextSpan(
              text: body,
              style: TextStyle(
                fontWeight: FontWeight.normal,
                color: textColor.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      );
    }
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: textColor.withValues(alpha: 0.9),
        height: 1.4,
      ),
    );
  }

  /// 左右分栏区域
  Widget _buildSplitSection(
    BuildContext context,
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左边：工程配置建议（可直接复制）
        Expanded(
          flex: 5,
          child: HarmonyProfileConfigCard(
            item: item,
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
          ),
        ),
        const SizedBox(width: 12),
        // 右边：平台核心能力、安全隐私、设备形态
        Expanded(
          flex: 5,
          child: Column(
            children: [
              _buildCapabilityCard(
                title: '平台核心能力',
                items: item.core,
                cardBg: cardBg,
                cardBorder: cardBorder,
                textPrimary: textPrimary,
              ),
              const SizedBox(height: 10),
              _buildCapabilityCard(
                title: '安全与隐私保护',
                items: item.privacy,
                cardBg: cardBg,
                cardBorder: cardBorder,
                textPrimary: textPrimary,
              ),
              const SizedBox(height: 10),
              // 适配设备形态
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '适配设备形态',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: ['手机', '平板', 'PC(2in1)', '智慧屏'].map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 能力列表卡片
  Widget _buildCapabilityCard({
    required String title,
    required List<String> items,
    required Color cardBg,
    required Color cardBorder,
    required Color textPrimary,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          ...items.map(
            (it) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Text(
                '• $it',
                style: TextStyle(
                  fontSize: 11.5,
                  color: textPrimary.withValues(alpha: 0.8),
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部文档链接
  Widget _buildDocLink(BuildContext context) {
    return InkWell(
      onTap: () => onOpenUrl(item.link),
      child: Text(
        item.link,
        style: const TextStyle(
          fontSize: 11.5,
          color: Color(0xFF0969DA),
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
