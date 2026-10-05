import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../common/utils/network_util.dart';
import '../../../core/providers/host_network_provider.dart';

/// 设备 IP 后的网段提示，通过 `DeviceSubnetWarning(wifiIp: device.wifiIp!)` 使用。
///
/// [wifiIp] 是设备当前展示的 IPv4。复用底栏网络快照，切网及手动刷新时重算；
/// 加载、读取失败或地址未知时不展示，不单独扫描网卡或执行 Ping。
class DeviceSubnetWarning extends ConsumerWidget {
  const DeviceSubnetWarning({super.key, required this.wifiIp});

  final String wifiIp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showWarning = ref.watch(
      hostNetworkProvider.select((network) {
        final info = network.asData?.value;
        if (info == null) return false;
        return NetworkLanMatcher.matchesAnySubnet(wifiIp, [
              if (info.address != null) info.address!.ipv4,
              ...info.ipv4Addresses.map((entry) => entry.ipv4),
            ]) ==
            false;
      }),
    );
    if (!showWarning) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: context.l10n.t('deviceSubnetWarning'),
        child: Icon(
          CupertinoIcons.exclamationmark_circle_fill,
          color: Theme.of(context).colorScheme.tertiary,
          size: 14,
        ),
      ),
    );
  }
}
