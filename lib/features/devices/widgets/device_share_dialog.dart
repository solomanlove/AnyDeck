import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/device_share/device_share_provider.dart';
import '../../../core/device_share/hosted_device_share.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/host_network_provider.dart';

/// 单设备共享与接收弹窗；device 为空时提供分享码连接和会话管理。
/// 通过 showDialog(builder: (_) => DeviceShareDialog(device: device)) 打开。
class DeviceShareDialog extends ConsumerStatefulWidget {
  const DeviceShareDialog({super.key, this.device});
  final RegisteredDevice? device;

  @override
  ConsumerState<DeviceShareDialog> createState() => _DeviceShareDialogState();
}

class _DeviceShareDialogState extends ConsumerState<DeviceShareDialog> {
  final _code = TextEditingController();
  String? _host, _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = 'deviceShareFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(deviceShareChangesProvider);
    final service = ref.read(deviceShareServiceProvider);
    final network = ref.watch(hostNetworkProvider).value;
    final addresses = <String>{
      if (network?.address case final address?) address.ipv4,
      ...?network?.ipv4Addresses.map((address) => address.ipv4),
    }.toList();
    final host = addresses.contains(_host) ? _host : addresses.firstOrNull;
    final device = widget.device;
    final hosted = service.hosts
        .where((share) => share.deviceId == device?.preferredCommandId)
        .firstOrNull;
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.t('deviceShare')),
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.t('deviceShareDescription')),
            const SizedBox(height: 16),
            if (device != null && hosted == null) ...[
              Text(
                device.displayName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              if (addresses.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: host,
                  decoration: InputDecoration(
                    labelText: l10n.t('deviceShareAddress'),
                  ),
                  items: [
                    for (final address in addresses)
                      DropdownMenuItem(value: address, child: Text(address)),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _host = value),
                )
              else
                Text(l10n.t('deviceShareNoNetwork')),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy || host == null || !device.isOnline
                    ? null
                    : () => _run(() async {
                        await service.share(
                          device.preferredCommandId,
                          device.displayName,
                          host,
                        );
                      }),
                icon: const Icon(Icons.share_outlined),
                label: Text(l10n.t('deviceShareStart')),
              ),
            ],
            if (hosted != null) _hostCard(hosted),
            if (device == null) ...[
              TextField(
                controller: _code,
                maxLines: 3,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.t('deviceShareCode'),
                  hintText: 'anydeck-share://…',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await service.join(_code.text);
                        _code.clear();
                      }),
                icon: const Icon(Icons.link),
                label: Text(l10n.t('deviceShareJoin')),
              ),
              for (final share in service.hosts) _hostCard(share),
            ],
            for (final joined in service.joins) ...[
              const Divider(height: 24),
              Text(
                joined.invitation.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SelectableText('${joined.invitation.host} → ${joined.deviceId}'),
              TextButton(
                onPressed: _busy ? null : () => _run(joined.close),
                child: Text(l10n.t('deviceShareLeave')),
              ),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  l10n.t(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.t('close')),
        ),
      ],
    );
  }

  Widget _hostCard(HostedDeviceShare share) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            share.invitation.name,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            l10n.t(share.connected ? 'deviceShareInUse' : 'deviceShareWaiting'),
          ),
          if (share.receiver != null) Text(share.receiver!),
          const SizedBox(height: 8),
          SelectableText(share.invitation.encode()),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: share.invitation.encode()),
                ),
                icon: const Icon(Icons.copy, size: 16),
                label: Text(l10n.t('deviceShareCopy')),
              ),
              TextButton(
                onPressed: _busy ? null : () => _run(share.close),
                child: Text(l10n.t('deviceShareStop')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
