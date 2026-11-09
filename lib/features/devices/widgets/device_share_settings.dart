import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/device_share/device_share_models.dart';
import '../../../core/network/host_network_info.dart';

/// 共享时长与指定 Wi-Fi 自动准备表单；回调交给弹窗执行保存和会话启停。
/// [wifiSsid] 是已选规则，只有系统确认当前 Wi-Fi 后才能开启新的自动规则。
class DeviceShareSettings extends StatelessWidget {
  const DeviceShareSettings({
    super.key,
    required this.lifetime,
    required this.automatic,
    required this.wifiSsid,
    required this.network,
    required this.busy,
    required this.onLifetimeChanged,
    required this.onAutomaticChanged,
    required this.onReadWifi,
  });
  final DeviceShareLifetime lifetime;
  final bool automatic, busy;
  final String? wifiSsid;
  final HostNetworkInfo? network;
  final ValueChanged<DeviceShareLifetime> onLifetimeChanged;
  final ValueChanged<bool> onAutomaticChanged;
  final VoidCallback onReadWifi;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentWifi = network?.isWifiAddress == true
        ? network?.verifiedWifiSsid
        : null;
    final selectedWifi = automatic ? wifiSsid ?? currentWifi : currentWifi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<DeviceShareLifetime>(
          key: ValueKey(lifetime),
          initialValue: lifetime,
          decoration: InputDecoration(labelText: l10n.t('deviceShareLifetime')),
          items: [
            for (final value in DeviceShareLifetime.values)
              DropdownMenuItem(
                value: value,
                child: Text(l10n.t(value.labelKey)),
              ),
          ],
          onChanged: busy
              ? null
              : (value) {
                  if (value != null) onLifetimeChanged(value);
                },
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.t('deviceShareAutoPrepare')),
          subtitle: Text(
            selectedWifi == null
                ? l10n.t('deviceShareAutoWifiUnavailable')
                : l10n
                      .t('deviceShareAutoPrepareDescription')
                      .replaceAll('{wifi}', selectedWifi),
          ),
          value: automatic,
          onChanged: busy || !automatic && currentWifi == null
              ? null
              : onAutomaticChanged,
        ),
        if (currentWifi == null)
          TextButton.icon(
            onPressed: busy ? null : onReadWifi,
            icon: const Icon(Icons.wifi_find_outlined, size: 18),
            label: Text(l10n.t('deviceShareReadWifi')),
          ),
      ],
    );
  }
}
