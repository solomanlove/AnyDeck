import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/modules/registered_device_model.dart';

/// 在设备编辑弹窗展示 [device] 已使用过的模拟器端口，并标注当前在线连接。
class DeviceConnectionHistory extends StatelessWidget {
  const DeviceConnectionHistory({super.key, required this.device});

  final RegisteredDevice device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('deviceConnectionHistory'),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        ...device.connectionHistory.reversed.map(
          (id) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 8,
              children: [
                SelectableText(id, style: theme.textTheme.bodySmall),
                if (device.isOnline && device.connections.contains(id))
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
