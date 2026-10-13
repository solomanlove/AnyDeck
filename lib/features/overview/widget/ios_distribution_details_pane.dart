import 'package:flutter/material.dart';

import '../../../app/theme/app_icon.dart';
import '../model/ios_version_distribution_data.dart';

/// iOS 版本特性、工具链对应矩阵与口径说明详情面板。
///
/// 包含 Apple 徽标 Hero、Xcode/Swift 工具链对应矩阵、口径边界声明卡片、
/// 编译与适配要求，以及平台核心与安全能力。
class IosDistributionDetailsPane extends StatelessWidget {
  /// 构造函数
  const IosDistributionDetailsPane({
    super.key,
    required this.item,
    required this.onOpenUrl,
  });

  /// 当前选中的 iOS 版本明细项
  final IosDistributionItem item;

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

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 顶部 Hero：Apple 灰色矢量图标 + 大标题 + 副标题
          _buildHeroHeader(isDark, textPrimary, textSecondary),
          const SizedBox(height: 12),

          // 2. 概要说明
          Text(
            item.summary,
            style: TextStyle(
              fontSize: 12.5,
              color: textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),

          // 3. 工具链矩阵表格（Xcode / Swift / SDK / 部署目标）
          _buildToolchainMatrixTable(cardBg, cardBorder, textPrimary, textSecondary),
          const SizedBox(height: 14),

          // 4. 专属口径边界说明卡片
          _buildNoticeCard(isDark),
          const SizedBox(height: 14),

          // 5. 编译与适配要求卡片
          _buildImpactsCard(cardBg, cardBorder, textPrimary, textSecondary),
          const SizedBox(height: 14),

          // 6. 分割两列：平台核心与 AI 能力 + 安全与隐私保护
          _buildCapabilitiesSplit(cardBg, cardBorder, textPrimary),
          const SizedBox(height: 14),

          // 7. 底部开发者网站链接
          _buildDocLink(),
        ],
      ),
    );
  }

  /// 构建顶部 Hero 头部
  Widget _buildHeroHeader(
    bool isDark,
    Color textPrimary,
    Color textSecondary,
  ) {
    final appleBg = isDark ? const Color(0xFF383B40) : const Color(0xFFE8EAED);

    return Row(
      children: [
        // 苹果 Logo 圆角容器
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: appleBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Image.asset(
              AppIcons.apple,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              color: isDark ? Colors.white : const Color(0xFF1D1D1F),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'iOS ${item.version}',
              style: TextStyle(
                color: textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${item.minor} · 发布 ${item.date} · 数据源 ${item.source}',
              style: TextStyle(
                color: textSecondary,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 工具链对应矩阵表格
  Widget _buildToolchainMatrixTable(
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorder),
      ),
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(110),
          1: FlexColumnWidth(),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: cardBorder, width: 1),
        ),
        children: item.matrix.map((entry) {
          return TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// 专属口径说明卡片
  Widget _buildNoticeCard(bool isDark) {
    final noticeBg = isDark
        ? const Color(0xFF1E2836)
        : const Color(0xFFF0F6FD);
    final noticeBorder = isDark
        ? const Color(0xFF2C3E55)
        : const Color(0xFFD0E1FD);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: noticeBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: noticeBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Color(0xFF0969DA),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: const TextSpan(
                text: '口径说明：',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0969DA),
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text:
                        'Apple 官方仅公布「当前大版本采用率」，从未公布 iOS 历史版本分布；官方数据基于 App Store 交易设备统计（基准日 2026-06-07），与网页流量类第三方统计（基准日 2026-09-30）口径不同，两者不可直接相加或对比。本页 iOS 版本占比含第三方统计值，已在每行标注来源，仅用于趋势参考，不可作为 minSdk 决策依据。',
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      color: Color(0xFF57606A),
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

  /// 编译与适配要求卡片
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
                '◈ 编译与适配要求',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0969DA),
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

  /// 智能解析加粗小标题
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

  /// 平台核心与安全能力两列面板
  Widget _buildCapabilitiesSplit(
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildCapabilityBox(
            title: '平台核心与 AI 能力',
            items: item.core,
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildCapabilityBox(
            title: '安全与隐私保护',
            items: item.privacy,
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildCapabilityBox({
    required String title,
    required List<String> items,
    required Color cardBg,
    required Color cardBorder,
    required Color textPrimary,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
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
          const SizedBox(height: 6),
          ...items.map(
            (it) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
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

  /// 底部开发文档链接
  Widget _buildDocLink() {
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
