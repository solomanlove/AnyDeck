import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/device_share/device_share_provider.dart';
import '../../../core/device_share/device_share_models.dart';
import '../../../core/device_share/device_share_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/host_network_provider.dart';
import 'device_share_saved_cards.dart';
import 'device_share_settings.dart';

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
  String? _wifiSsid;
  DeviceShareLifetime _lifetime = DeviceShareLifetime.minutes30;
  bool _busy = false, _automatic = false, _dirty = false;

  @override
  void initState() {
    super.initState();
    ref.read(deviceShareServiceProvider).initialize().catchError((Object _) {
      if (mounted) setState(() => _error = 'deviceShareHistoryLoadFailed');
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    String failureKey = 'deviceShareFailed',
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error is StateError &&
                  error.message == 'deviceShareAutoNeedsIdentity'
              ? 'deviceShareAutoNeedsIdentity'
              : failureKey,
        );
      }
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
    final profile = service.profiles
        .where(
          (entry) =>
              entry.serial == device?.serial ||
              entry.deviceId == device?.preferredCommandId,
        )
        .firstOrNull;
    if (!_dirty && service.ready) {
      _lifetime = profile?.lifetime ?? DeviceShareLifetime.minutes30;
      _automatic = profile?.automaticallyPrepares ?? false;
      _wifiSsid = profile?.wifiSsid;
    }
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
            if (device != null) ...[
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
              DeviceShareSettings(
                lifetime: _lifetime,
                automatic: _automatic,
                wifiSsid: _wifiSsid,
                network: network,
                busy: _busy,
                onLifetimeChanged: (value) => setState(() {
                  _lifetime = value;
                  _dirty = true;
                }),
                onAutomaticChanged: (value) => setState(() {
                  _automatic = value;
                  _dirty = true;
                  if (value) {
                    _wifiSsid = network?.verifiedWifiSsid;
                  }
                }),
                onReadWifi: () => _run(
                  () => ref
                      .read(hostNetworkProvider.notifier)
                      .refresh(requestWifiAccess: true),
                ),
              ),
              const SizedBox(height: 12),
              if (hosted == null || _dirty)
                FilledButton.icon(
                  onPressed: _busy || host == null || !device.isOnline
                      ? null
                      : () => _run(() async {
                          await service.share(
                            device.preferredCommandId,
                            device.displayName,
                            _automatic && network?.isWifiAddress == true
                                ? network!.address!.ipv4
                                : host,
                            lifetime: _lifetime,
                            wifiSsid: _automatic ? _wifiSsid : null,
                            serial: device.serial,
                          );
                          if (mounted) setState(() => _dirty = false);
                        }),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(
                    l10n.t(
                      hosted == null ? 'deviceShareStart' : 'deviceShareApply',
                    ),
                  ),
                ),
            ],
            if (profile != null && device != null && hosted != null)
              _profileCard(service, profile),
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
              if (service.profiles.isNotEmpty) ...[
                const Divider(height: 24),
                Text(
                  l10n.t('deviceShareMyRules'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final profile in service.profiles)
                  _profileCard(service, profile),
              ],
              const Divider(height: 24),
              Text(
                l10n.t('deviceShareHistory'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (service.history.isEmpty)
                Text(l10n.t('deviceShareHistoryEmpty')),
              for (final entry in service.history)
                DeviceShareHistoryCard(
                  entry: entry,
                  busy: _busy,
                  connected: service.joins
                      .where(
                        (joined) => joined.invitation.fingerprint == entry.id,
                      )
                      .firstOrNull,
                  onReconnect: () => _run(() async {
                    await service.reconnect(entry.id);
                  }, failureKey: 'deviceShareReconnectFailed'),
                  onDisconnect: () => _run(() async {
                    await service.joins
                        .where(
                          (joined) => joined.invitation.fingerprint == entry.id,
                        )
                        .firstOrNull
                        ?.close();
                  }),
                  onForget: () => _run(() => service.forgetHistory(entry.id)),
                ),
            ],
            if (service.initializationError != null)
              Text(l10n.t('deviceShareHistoryLoadFailed')),
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

  Widget _profileCard(DeviceShareService service, SavedDeviceShare profile) =>
      DeviceShareProfileCard(
        profile: profile,
        expired: service.hasExpiredWindow(profile.id),
        busy: _busy,
        active: service.hosts
            .where((host) => host.invitation.fingerprint == profile.id)
            .firstOrNull,
        onResume: () => _run(() async {
          await service.resumeShare(
            profile.id,
            host: _host ?? ref.read(hostNetworkProvider).value?.address?.ipv4,
          );
        }),
        onStop: () => _run(() => service.stopShare(profile.id)),
        onForget: () => _run(() => service.forgetShare(profile.id)),
      );
}
