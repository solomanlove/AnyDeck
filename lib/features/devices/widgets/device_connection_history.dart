import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/modules/registered_device_model.dart';

/// 在设备编辑弹窗展示 [device] 曾用的模拟器端口、最近上线时间和当前连接。
class DeviceConnectionHistory extends StatelessWidget {
  const DeviceConnectionHistory({super.key, required this.device});

  final RegisteredDevice device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final timeStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('deviceConnectionHistory'),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        ...device.connectionHistory.reversed.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                SelectableText(entry.id, style: theme.textTheme.bodySmall),
                Text(
                  entry.connectedAt?.toLocal().toString().split('.').first ??
                      l10n.t('deviceConnectionTimeUnknown'),
                  style: timeStyle,
                ),
                if (device.isOnline && device.connections.contains(entry.id))
                  Text(
                    l10n.t('deviceCurrentConnection'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
