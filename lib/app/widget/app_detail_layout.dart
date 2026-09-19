import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 两类应用详情统一使用的 presentation data structure。
class AppDetailViewData {
  const AppDetailViewData({
    required this.name,
    required this.version,
    required this.logo,
    required this.fields,
    required this.tabs,
    this.badges = const [],
  });

  final String name;
  final String version;
  final AppDetailLogoData logo;
  final List<AppDetailSummaryBadge> badges;
  final List<AppDetailSummaryField> fields;
  final List<AppDetailTabData> tabs;
}

/// 应用 Logo 的统一展示数据，主图加载失败时回退到对应平台默认图标。
class AppDetailLogoData {
  const AppDetailLogoData({required this.fallbackImage, this.image});

  final ImageProvider<Object>? image;
  final ImageProvider<Object> fallbackImage;
}

/// 统一 Tab 标题与数量，Tab 内业务内容由对应 Adapter 注入。
class AppDetailTabData {
  const AppDetailTabData({required this.id, required this.title, this.count});

  final String id;
  final String title;
  final int? count;

  String get displayTitle => count == null ? title : '$title ($count)';
}

/// 红框区域唯一的顶层 UI，统一概要、分栏、TabBar 与 TabBarView。
class AppDetailView extends StatelessWidget {
  const AppDetailView({
    super.key,
    required this.data,
    required this.summaryBackground,
    this.tabViews = const [],
    this.tabBody,
    this.copyTooltip,
    this.onCopied,
  });

  final AppDetailViewData data;
  final List<Widget> tabViews;
  final Widget? tabBody;
  final Color summaryBackground;
  final String? copyTooltip;
  final ValueChanged<AppDetailSummaryField>? onCopied;

  @override
  Widget build(BuildContext context) {
    assert(
      tabBody != null || data.tabs.length == tabViews.length,
      'tabViews must match data.tabs when tabBody is not provided',
    );
    return DefaultTabController(
      length: data.tabs.length,
      child: AppDetailSplitView(
        summaryBackground: summaryBackground,
        summary: AppDetailSummaryPanel(
          name: data.name,
          version: data.version,
          logo: data.logo,
          badges: data.badges,
          fields: data.fields,
          copyTooltip: copyTooltip,
          onCopied: onCopied,
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final tab in data.tabs) Tab(text: tab.displayTitle)],
            ),
            const SizedBox(height: 10),
            Expanded(child: tabBody ?? TabBarView(children: tabViews)),
          ],
        ),
      ),
    );
  }
}

/// 应用详情页统一的左右分栏壳层，窄窗口下自动切换为上下布局。
class AppDetailSplitView extends StatelessWidget {
  const AppDetailSplitView({
    super.key,
    required this.summary,
    required this.content,
    required this.summaryBackground,
    this.breakpoint = 720,
    this.summaryWidth = 300,
    this.spacing = 24,
  });

  final Widget summary;
  final Widget content;
  final Color summaryBackground;
  final double breakpoint;
  final double summaryWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= breakpoint;
        final borderColor = Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.45);
        final summaryContainer = DecoratedBox(
          decoration: BoxDecoration(
            color: summaryBackground,
            border: Border(
              right: horizontal
                  ? BorderSide(color: borderColor)
                  : BorderSide.none,
              bottom: horizontal
                  ? BorderSide.none
                  : BorderSide(color: borderColor),
            ),
          ),
          child: summary,
        );

        if (horizontal) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: summaryWidth, child: summaryContainer),
              SizedBox(width: spacing),
              Expanded(child: content),
              SizedBox(width: spacing),
            ],
          );
        }

        final summaryHeight = (constraints.maxHeight * 0.42)
            .clamp(220.0, 420.0)
            .toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: summaryHeight, child: summaryContainer),
            SizedBox(height: spacing),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

/// 应用概要标签的主题色类型。
enum AppDetailBadgeTone { info, success, warning, error }

/// 应用概要顶部的 ABI、Framework 或状态标签。
class AppDetailSummaryBadge {
  const AppDetailSummaryBadge({
    required this.label,
    this.tone = AppDetailBadgeTone.info,
  });

  final String label;
  final AppDetailBadgeTone tone;
}

/// 应用概要中的单个字段，页面只负责准备业务数据。
class AppDetailSummaryField {
  const AppDetailSummaryField({
    required this.label,
    required this.value,
    this.copyable = false,
    this.valueColor,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final bool copyable;
  final Color? valueColor;
  final int maxLines;
}

/// 图二样式的应用概要面板，统一标题、标签、字段和复制操作。
class AppDetailSummaryPanel extends StatelessWidget {
  const AppDetailSummaryPanel({
    super.key,
    required this.name,
    required this.version,
    required this.logo,
    required this.fields,
    this.badges = const [],
    this.copyTooltip,
    this.onCopied,
  });

  final String name;
  final String version;
  final AppDetailLogoData logo;
  final List<AppDetailSummaryBadge> badges;
  final List<AppDetailSummaryField> fields;
  final String? copyTooltip;
  final ValueChanged<AppDetailSummaryField>? onCopied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AppDetailLogo(data: logo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      version,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 12),
            Center(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  for (final badge in badges) _AppDetailBadge(data: badge),
                ],
              ),
            ),
          ],
          const SizedBox(height: 5),
          const Divider(),
          const SizedBox(height: 5),
          for (final field in fields)
            _AppDetailFieldRow(
              field: field,
              copyTooltip: copyTooltip,
              onCopied: onCopied,
            ),
        ],
      ),
    );
  }
}

class _AppDetailLogo extends StatelessWidget {
  const _AppDetailLogo({required this.data});

  final AppDetailLogoData data;

  @override
  Widget build(BuildContext context) {
    Widget fallback() {
      return Image(
        image: data.fallbackImage,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.android,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 40,
        ),
      );
    }

    return ClipRRect(
      key: const ValueKey('app-detail-logo'),
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 72,
        height: 72,
        child: data.image == null
            ? fallback()
            : Image(
                image: data.image!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => fallback(),
              ),
      ),
    );
  }
}

class _AppDetailBadge extends StatelessWidget {
  const _AppDetailBadge({required this.data});

  final AppDetailSummaryBadge data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = switch (data.tone) {
      AppDetailBadgeTone.info => colorScheme.primary,
      AppDetailBadgeTone.success => const Color(0xFF2E7D32),
      AppDetailBadgeTone.warning => const Color(0xFFEF6C00),
      AppDetailBadgeTone.error => colorScheme.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        data.label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AppDetailFieldRow extends StatelessWidget {
  const _AppDetailFieldRow({
    required this.field,
    required this.copyTooltip,
    required this.onCopied,
  });

  final AppDetailSummaryField field;
  final String? copyTooltip;
  final ValueChanged<AppDetailSummaryField>? onCopied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Tooltip(
                  message: field.value,
                  waitDuration: const Duration(milliseconds: 500),
                  child: Text(
                    field.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: field.valueColor,
                    ),
                    maxLines: field.maxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (field.copyable) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 14),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: field.value));
                    onCopied?.call(field);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  splashRadius: 16,
                  tooltip: copyTooltip,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
