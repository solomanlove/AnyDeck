import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/device_share/device_share_provider.dart';
import '../../../core/providers/app_providers.dart';
import 'device_share_dialog.dart';

/// 设备行共享按钮；本地 Android 可创建共享，共享来源可主动断开。
/// device 使用合并后的注册表快照，以便双通道设备始终绑定实际命令通道。
class DeviceShareControls extends ConsumerWidget {
  const DeviceShareControls({super.key, required this.device});
  final RegisteredDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (device.isIos || device.isHarmony || device.id.startsWith('emulator-')) {
      return const SizedBox.shrink();
    }
    ref.watch(deviceShareChangesProvider);
    final service = ref.read(deviceShareServiceProvider);
    final joined = service.joins
        .where(
          (j) =>
              j.deviceId == device.id ||
              device.connections.contains(j.deviceId),
        )
        .firstOrNull;
    final active = service.hosts.any(
      (h) => h.deviceId == device.preferredCommandId,
    );
    return IconButton(
      tooltip: context.l10n.t(
        device.isShared
            ? 'deviceShareLeave'
            : active
            ? 'deviceShareManage'
            : 'deviceShare',
      ),
      icon: Icon(
        device.isShared ? Icons.link_off : Icons.share_outlined,
        size: 21,
      ),
      color: active ? Theme.of(context).colorScheme.primary : null,
      onPressed: device.isShared
          ? joined?.close
          : !device.isOnline
          ? null
          : () => showDialog<void>(
              context: context,
              builder: (_) => DeviceShareDialog(device: device),
            ),
    );
  }
}
