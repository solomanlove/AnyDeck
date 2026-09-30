import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/app_toast.dart';
import '../../../core/adb/adb_result.dart';
import '../../../core/providers/app_providers.dart';

/// Android 操作列无线按钮，统一提供连接、断开及操作进度。
/// device 必须是注册表合并后的设备，便于所有入口共享身份、防重复与进度。
class DeviceWirelessControls extends ConsumerWidget {
  const DeviceWirelessControls({
    super.key,
    required this.device,
  });
  final RegisteredDevice device;

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
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!device.isOnline || !device.hasTcpConnection || busy)
          IconButton(
            tooltip: context.l10n.t('wirelessConnect'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    // 无论是否曾失败，此按钮职责始终为发起无线连接，保持连接图标
                    CupertinoIcons.link,
                    size: 22,
                    color: colors.primary,
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
        if (networkIds.isNotEmpty) ...[
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
    // 设备已在线且已成功建立无线连接（TCP/WiFi调试），历史失败提示不再显示
    if (device.isOnline &&
        (device.hasTcpConnection || device.hasWifiDebuggingConnection) &&
        !status.busy) {
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
