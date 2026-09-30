import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/app_toast.dart';
import '../../../core/adb/adb_result.dart';
import '../../../core/providers/app_providers.dart';

/// Android 单设备无线按钮。compact 用于名称旁的快捷入口；默认同时提供断开。
/// device 必须是注册表合并后的设备，便于所有入口共享身份、防重复与进度。
class DeviceWirelessControls extends ConsumerWidget {
  const DeviceWirelessControls({
    super.key,
    required this.device,
    this.compact = false,
  });
  final RegisteredDevice device;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (device.id.startsWith('emulator-')) return const SizedBox.shrink();
    final status = ref.watch(
      wirelessConnectionProvider.select(
        (states) => wirelessStateFor(states, device),
      ),
    );
    final busy = status?.busy ?? false;
    final colors = Theme.of(context).colorScheme;
    final networkIds = device.isOnline
        ? device.connections.where((id) => !isPhysicalUsbId(id)).toList()
        : <String>[];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!device.isOnline || !device.hasTcpConnection || busy)
          IconButton(
            tooltip: context.l10n.t(status?.messageKey ?? 'wirelessConnect'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: busy
                ? SizedBox(
                    width: compact ? 16 : 20,
                    height: compact ? 16 : 20,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    status?.failed == true
                        ? Icons.link_off
                        : CupertinoIcons.link,
                    size: compact ? 16 : 22,
                    color: status?.failed == true
                        ? colors.error
                        : colors.primary,
                  ),
            onPressed: busy
                ? null
                : () async {
                    final result = await ref
                        .read(deviceRegistryProvider.notifier)
                        .connectPreferredWireless(device);
                    if (!context.mounted) return;
                    _showResult(context, result);
                  },
          ),
        if (!compact && networkIds.isNotEmpty) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: context.l10n.t('disconnect'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(CupertinoIcons.bolt_slash, color: colors.error),
            onPressed: busy
                ? null
                : () async {
                    AdbResult? failure;
                    for (final id in networkIds) {
                      final result = await ref
                          .read(deviceRegistryProvider.notifier)
                          .disconnectDevice(id);
                      if (!result.isSuccess) failure = result;
                    }
                    if (!context.mounted) return;
                    if (failure != null) {
                      _showResult(context, failure);
                    } else {
                      AppToast.show(
                        context,
                        context.l10n.t('wirelessDisconnected'),
                      );
                    }
                  },
          ),
        ],
      ],
    );
  }

  void _showResult(BuildContext context, AdbResult result) {
    AppToast.show(
      context,
      result is AdbWirelessResult
          ? context.l10n.t(result.messageKey)
          : result.message,
      isError: !result.isSuccess,
    );
  }
}

/// 自动准备和回退状态直接展示在设备行；失败原因无需点击即可看到。
class DeviceWirelessStatusLabel extends ConsumerWidget {
  const DeviceWirelessStatusLabel({super.key, required this.device});
  final RegisteredDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      wirelessConnectionProvider.select(
        (states) => wirelessStateFor(states, device),
      ),
    );
    if (status == null || (!status.busy && !status.failed)) {
      return const SizedBox.shrink();
    }
    final text = context.l10n.t(status.messageKey);
    return Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: status.failed
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
