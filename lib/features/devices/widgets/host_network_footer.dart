import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/network/host_network_info.dart';
import '../../../core/providers/host_network_provider.dart';

/// 设备列表固定底栏：展示当前电脑主机的 Wi-Fi/热点名称和本机 IP 地址。
///
/// 位于设备管理列表最下方，窄窗口自动换行，离开页面时自动释放网络监听。
class HostNetworkFooter extends ConsumerWidget {
  const HostNetworkFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(hostNetworkProvider);
    final info = network.asData?.value;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final placeholder = l10n.t(
      network.isLoading ? 'hostNetworkLoading' : 'hostNetworkUnavailable',
    );
    final wifi = info?.ssid ??
        (info == null
            ? placeholder
            : l10n.t(switch (info.wifiStatus) {
                HostWifiStatus.disconnected => 'hostWifiDisconnected',
                HostWifiStatus.permissionRequired => 'hostWifiPermissionRequired',
                _ => 'hostNetworkUnavailable',
              }));
    final address = info?.address;
    final iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: DefaultTextStyle(
        style: theme.textTheme.bodySmall!.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 当前电脑主机标识
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.laptop_mac_outlined, size: 14, color: iconColor),
                const SizedBox(width: 4),
                Text(l10n.t('hostNetworkComputer')),
              ],
            ),
            // Wi-Fi / 热点名称
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi, size: 14, color: iconColor),
                const SizedBox(width: 4),
                Text('${l10n.t('hostNetworkWifi')}: $wifi'),
              ],
            ),
            // 本机 IPv4 地址
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lan_outlined, size: 14, color: iconColor),
                const SizedBox(width: 4),
                SelectableText(
                  '${l10n.t(info?.isWifiAddress == true ? 'hostNetworkWifiIp' : 'hostNetworkIp')}: '
                  '${address?.ipv4 ?? placeholder}'
                  '${address == null ? '' : ' (${address.interfaceName})'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            // 需要权限时提示授权按钮
            if (info?.wifiStatus == HostWifiStatus.permissionRequired)
              TextButton(
                onPressed: network.isLoading
                    ? null
                    : () => ref.read(hostNetworkProvider.notifier).refresh(
                        requestWifiAccess: true,
                      ),
                child: Text(l10n.t('hostWifiReadName')),
              ),
            // 刷新按钮
            IconButton(
              tooltip: l10n.t('hostNetworkRefresh'),
              visualDensity: VisualDensity.compact,
              onPressed: network.isLoading
                  ? null
                  : () => ref.read(hostNetworkProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}
