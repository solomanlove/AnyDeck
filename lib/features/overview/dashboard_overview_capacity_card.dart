part of '../dashboard_screen.dart';

/// 内存与存储共用的容量卡，保持左右布局和跳转交互一致。
class _OverviewCapacityCard extends ConsumerWidget {
  const _OverviewCapacityCard({
    required this.label,
    required this.icon,
    required this.value,
    required this.deviceId,
    required this.targetTab,
  });

  final String label;
  final IconData icon;
  final String value;
  final String deviceId;
  final int targetTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = _StorageUsage.parse(value);
    return _OverviewHeroCard(
      icon: icon,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        mouseCursor: SystemMouseCursors.click,
        onTap: () => context.goNamed(
          AppRouteNames.deviceTool,
          pathParameters: {
            'deviceId': deviceId,
            'tool': toolSlugForTabIndex(targetTab),
          },
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.t('overviewUsedTotal'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (usage != null) ...[
                const SizedBox(height: 8),
                Text(
                  context.l10n
                      .t('usedPercent')
                      .replaceAll('{percent}', usage.percent.toString()),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: usage.ratio,
                    color: _overviewAccent,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
