part of '../dashboard_screen.dart';

class _OverviewHeroCard extends StatelessWidget {
  const _OverviewHeroCard({
    required this.icon,
    required this.label,
    required this.child,
    this.onTap,
    this.tooltip,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _OverviewIconBadge(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 6),
                      trailing!,
                    ] else if (tooltip != null) ...[
                      const SizedBox(width: 6),
                      _OverviewInfoTooltip(
                        message: tooltip!,
                        child: Icon(
                          CupertinoIcons.info_circle,
                          size: 17,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
    return _OverviewSurface(
      accent: true,
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: BorderRadius.circular(16),
              mouseCursor: SystemMouseCursors.click,
              onTap: onTap,
              child: content,
            ),
    );
  }
}

/// 仅悬浮 info icon 时展示 Android API 对应关系。
class _OverviewInfoTooltip extends StatelessWidget {
  const _OverviewInfoTooltip({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: message,
      preferBelow: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.all(8),
      verticalOffset: 24,
      textStyle: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: Colors.white,
        height: 1.4,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.grey[900]!.withAlpha(242)
            : Colors.black.withAlpha(217),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withAlpha(31)
              : Colors.white.withAlpha(51),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(64),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _OverviewDetailCard extends StatelessWidget {
  const _OverviewDetailCard({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<_OverviewDetailData> items;

  @override
  Widget build(BuildContext context) {
    return _OverviewSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: _overviewAccent, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            _OverviewDetailRow(data: items[index]),
          ],
        ],
      ),
    );
  }
}

class _OverviewDetailRow extends StatelessWidget {
  const _OverviewDetailRow({required this.data});

  final _OverviewDetailData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget child = LayoutBuilder(
      builder: (context, constraints) {
        final label = Text(
          data.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
        final value = Text(
          data.value,
          textAlign: TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        );
        if (constraints.maxWidth < 320) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [label, const SizedBox(height: 4), value],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: constraints.maxWidth * 0.34, child: label),
            const SizedBox(width: 16),
            Expanded(child: value),
          ],
        );
      },
    );

    child = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _copyOverviewValue(context, data.label, data.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: child,
      ),
    );

    if (data.tooltip == null) {
      return child;
    }
    return Tooltip(message: data.tooltip!, child: child);
  }
}

class _OverviewSurface extends StatelessWidget {
  const _OverviewSurface({required this.child, this.accent = false});

  final Widget child;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent
                ? _overviewAccent.withValues(alpha: isDark ? 0.08 : 0.045)
                : theme.colorScheme.surface.withValues(
                    alpha: isDark ? 0.3 : 0.55,
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent
                  ? _overviewAccent.withValues(alpha: isDark ? 0.35 : 0.25)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    );
  }
}

class _OverviewIconBadge extends StatelessWidget {
  const _OverviewIconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: _overviewAccent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: _overviewAccent, size: 22),
    );
  }
}

class _OverviewBadge extends StatelessWidget {
  const _OverviewBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _overviewAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _overviewAccent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _OverviewIdentityData {
  const _OverviewIdentityData({
    required this.icon,
    required this.value,
    this.label,
    this.secondary,
  });

  final IconData icon;
  final String value;
  final String? label;
  final String? secondary;
}

class _OverviewDetailData {
  const _OverviewDetailData({
    required this.label,
    required this.value,
    this.tooltip,
  });

  final String label;
  final String value;
  final String? tooltip;
}

class _VersionDisplay {
  const _VersionDisplay(this.version, this.api);

  final String version;
  final String? api;

  factory _VersionDisplay.parse(String value) {
    final match = RegExp(r'^(.*?)\s*\((API\s+\d+)\)\s*$').firstMatch(value);
    if (match == null) {
      return _VersionDisplay(value, null);
    }
    return _VersionDisplay(match.group(1)!.trim(), match.group(2));
  }
}

class _StorageUsage {
  const _StorageUsage(this.ratio);

  final double ratio;
  int get percent => (ratio * 100).round();

  static _StorageUsage? parse(String value) {
    final numbers = RegExp(r'\d+(?:\.\d+)?')
        .allMatches(value)
        .map((match) => double.tryParse(match.group(0)!))
        .whereType<double>()
        .toList();
    if (numbers.length < 2 || numbers[1] <= 0) {
      return null;
    }
    return _StorageUsage((numbers[0] / numbers[1]).clamp(0.0, 1.0));
  }
}

Future<void> _copyOverviewValue(
  BuildContext context,
  String label,
  String value,
) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) {
    return;
  }
  _showSnack(
    context,
    context.l10n.t('copiedToClipboard').replaceAll('{label}', label),
  );
}
