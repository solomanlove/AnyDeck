import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/providers/modules/registered_device_model.dart';
import '../model/device_list_presentation.dart';

/// 设备标识旁的只读 USB / TCP / TLS / iOS 网络通道状态，不提供连接操作。
///
/// [device] 为合并后的设备，[isAirplayMirroring] 表示独立的投屏会话。
/// 默认并排显示小图标并消费点击，避免触发外层设备行的概览导航；
/// [showLabels] 为 true 时纵向展示图标和短名称，保留父级行的点击与批量选择。
class DeviceConnectionIndicators extends StatelessWidget {
  const DeviceConnectionIndicators({
    super.key,
    required this.device,
    this.isAirplayMirroring = false,
    this.showLabels = false,
  });

  /// 包含在线状态及合并后连接通道的设备快照。
  final RegisteredDevice device;

  /// AirPlay 会话不依赖 USB、TCP 或 iOS 调试连接是否在线。
  final bool isAirplayMirroring;

  /// 列表连接列使用的紧凑纵向文案模式；默认维持原图标展示。
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final connections = DeviceListPresentation.connections(
      device,
      isAirplayMirroring: isAirplayMirroring,
    );
    if (showLabels) return _buildLabels(context, connections);
    if (connections.isEmpty) return const SizedBox.shrink();

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () {},
        onDoubleTap: () {},
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final connection in connections)
              _indicator(context, connection),
          ],
        ),
      ),
    );
  }

  /// 同一份通道集合生成视觉标签及一条完整语义，避免读屏重复短名称。
  Widget _buildLabels(
    BuildContext context,
    List<DeviceConnectionKind> connections,
  ) {
    final theme = Theme.of(context);
    if (connections.isEmpty) {
      final label = context.l10n.t(
        device.isOnline
            ? 'connectionUnknown'
            : DeviceListPresentation.statusKey(device),
      );
      return Semantics(
        label: label,
        excludeSemantics: true,
        child: _label(
          context,
          label: label,
          fullLabel: label,
          icon: device.isOnline ? Icons.help_outline : Icons.link_off_rounded,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Semantics(
      label: connections
          .map((connection) => context.l10n.t(connection.fullLabelKey))
          .join(', '),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < connections.length; index++) ...[
            if (index > 0) const SizedBox(height: 2),
            _label(
              context,
              label: context.l10n.t(connections[index].shortLabelKey),
              fullLabel: context.l10n.t(connections[index].fullLabelKey),
              icon: _icon(connections[index]),
              color: theme.appColors.success,
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(
    BuildContext context, {
    required String label,
    required String fullLabel,
    required IconData icon,
    required Color color,
  }) => Tooltip(
    message: fullLabel,
    excludeFromSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            softWrap: true,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 11,
              height: 1.15,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _indicator(BuildContext context, DeviceConnectionKind connection) {
    final color = switch (connection) {
      DeviceConnectionKind.usb => const Color(0xFF26A69A),
      DeviceConnectionKind.tcp => const Color(0xFF00ACC1),
      DeviceConnectionKind.wireless => const Color(0xFF43A047),
      DeviceConnectionKind.iosNetwork ||
      DeviceConnectionKind.airplay => Theme.of(context).colorScheme.primary,
    };
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: context.l10n.t(switch (connection) {
          DeviceConnectionKind.usb => 'connectionUsb',
          DeviceConnectionKind.airplay => 'airplayServer',
          _ => connection.fullLabelKey,
        }),
        child: Icon(_icon(connection), color: color, size: 16),
      ),
    );
  }

  IconData _icon(DeviceConnectionKind connection) => switch (connection) {
    DeviceConnectionKind.usb => Icons.usb,
    DeviceConnectionKind.tcp => CupertinoIcons.link,
    DeviceConnectionKind.wireless ||
    DeviceConnectionKind.iosNetwork => CupertinoIcons.wifi,
    DeviceConnectionKind.airplay => Icons.airplay_rounded,
  };
}
