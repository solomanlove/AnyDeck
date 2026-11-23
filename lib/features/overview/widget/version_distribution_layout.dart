import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 主窗口和独立窗口共用的版本资料页。将标题栏传给 [header]、平台视图传给
/// [body]、日期和操作传给 [footer]。高度不足时整页可上下滚动。
class VersionDistributionPageLayout extends StatelessWidget {
  const VersionDistributionPageLayout({
    super.key,
    required this.header,
    required this.body,
    required this.footer,
  });

  final Widget header;
  final Widget body;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: header),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 320 为正文的最小阅读高度，剩余空间由 Expanded 分配给正文。
              Expanded(child: SizedBox(height: 320, child: body)),
              footer,
            ],
          ),
        ),
      ],
    );
  }
}

/// 系统版本页的列表和详情布局。将本组件放入高度受限的内容区，
/// 传入可纵向滚动的 [list] 和 [details]，窄窗口会将两者上下排列。
class VersionDistributionLayout extends StatelessWidget {
  const VersionDistributionLayout({
    super.key,
    required this.list,
    required this.details,
    required this.listWidth,
    required this.dividerColor,
  });

  final Widget list;
  final Widget details;

  /// 左右分栏时列表的最大宽度。
  final double listWidth;

  /// 两个区域之间的分隔线颜色。
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 将断点按正文字号换算，放大字体后仍给每列留足阅读空间。
        final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final stacked = constraints.maxWidth < 720 * textScale;
        return Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: stacked
                  ? null
                  : math.min(listWidth, constraints.maxWidth * 0.4),
              height: stacked ? constraints.maxHeight * 0.35 : null,
              child: list,
            ),
            SizedBox(
              width: stacked ? null : 1,
              height: stacked ? 1 : null,
              child: ColoredBox(color: dividerColor),
            ),
            Expanded(child: details),
          ],
        );
      },
    );
  }
}

/// 带表头的纵向版本列表。[header] 为列标题，[rows] 为构建行的 Sliver。
/// 列表变矮或字号放大时，表头随行滚动，确保用户仍可选择版本。
class VersionDistributionList extends StatelessWidget {
  const VersionDistributionList({
    super.key,
    required this.header,
    required this.rows,
  });

  final Widget header;
  final Widget rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final headerScale = MediaQuery.textScalerOf(context).scale(11) / 11;
        final scrollHeader = constraints.maxHeight < 140 * headerScale;
        return Column(
          children: [
            if (!scrollHeader) header,
            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (scrollHeader) SliverToBoxAdapter(child: header),
                  rows,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 在版本详情中依次传入 [first]、[second] 两组资料。空间充足时两组等宽
/// 并排，较窄时按阅读顺序上下排列；[spacing] 为两组之间的间距。
class VersionDetailColumns extends StatelessWidget {
  const VersionDetailColumns({
    super.key,
    required this.first,
    required this.second,
    this.spacing = 12,
  });

  final Widget first;
  final Widget second;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
        if (constraints.maxWidth < 600 * textScale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: spacing,
            children: [first, second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: spacing,
          children: [
            Expanded(child: first),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
