part of '../dashboard_screen.dart';

/// 概览身份卡以中性灰展示电量；满电时省略状态文字，未知数据使用占位。
class _OverviewBatteryChip extends StatelessWidget {
  const _OverviewBatteryChip({required this.battery});

  final DeviceBatteryInfo? battery;

  @override
  Widget build(BuildContext context) {
    final level = battery?.level;
    final state = battery?.chargingState ?? DeviceChargingState.unknown;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final stateKey = switch (state) {
      DeviceChargingState.charging => 'batteryCharging',
      DeviceChargingState.notCharging => 'batteryNotCharging',
      DeviceChargingState.full => null,
      DeviceChargingState.unknown =>
        level == null ? 'batteryUnknown' : 'chargeStatusUnknown',
    };
    final icon = level == null
        ? CupertinoIcons.battery_0
        : level <= 25
        ? CupertinoIcons.battery_25
        : level < 80
        ? CupertinoIcons.battery_75_percent
        : CupertinoIcons.battery_100;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 6),
            Text(
              level == null ? '--%' : '$level%',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (stateKey != null) ...[
              const SizedBox(width: 6),
              Text(
                context.l10n.t(stateKey),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
