import 'package:flutter/material.dart';

import '../../../../core/scrcpy/mirror_transport_type.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme_sizes.dart';

/// 设备信息卡的名称与实际投屏通道；长名称省略时仍完整保留通道标签。
/// [transport] 仅由当前 Android 会话路由提供，未指定时只显示设备名称。
class MirrorDeviceNameHeading extends StatelessWidget {
  const MirrorDeviceNameHeading({
    super.key,
    required this.name,
    this.transport,
  });

  final String name;
  final MirrorTransportType? transport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (transport != null) ...[
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: AppThemeSizes.radiusSmall,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                context.l10n.t(transport!.labelKey),
                key: const Key('mirrorTransportBadge'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
