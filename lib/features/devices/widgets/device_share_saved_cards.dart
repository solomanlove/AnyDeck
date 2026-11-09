import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/device_share/device_share_models.dart';
import '../../../core/device_share/hosted_device_share.dart';
import '../../../core/device_share/joined_device_share.dart';

/// 保存的分享方规则；[active] 决定等待/连接状态，启停和删除由服务回调处理。
class DeviceShareProfileCard extends StatelessWidget {
  const DeviceShareProfileCard({
    super.key,
    required this.profile,
    required this.active,
    required this.busy,
    required this.onResume,
    required this.onStop,
    required this.onForget,
    this.expired = false,
  });
  final SavedDeviceShare profile;
  final HostedDeviceShare? active;
  final bool busy;
  final bool expired;
  final VoidCallback onResume, onStop, onForget;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final share = active;
    final deadline = share?.invitation.expiresAt;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(profile.name, style: Theme.of(context).textTheme.titleSmall),
          Text(
            l10n.t(
              share != null
                  ? share.connected
                        ? 'deviceShareInUse'
                        : 'deviceShareWaiting'
                  : profile.automaticallyPrepares
                  ? expired
                        ? 'deviceShareExpired'
                        : 'deviceShareAutoWaiting'
                  : 'deviceShareStopped',
            ),
          ),
          Text(l10n.t(profile.lifetime.labelKey)),
          if (profile.wifiSsid != null)
            Text('${l10n.t('hostNetworkWifi')}: ${profile.wifiSsid}'),
          if (deadline != null)
            Text(
              '${l10n.t('deviceShareExpiresAt')}: ${_date(context, deadline)}',
            ),
          if (share != null) ...[
            const SizedBox(height: 8),
            SelectableText(share.invitation.encode()),
          ],
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (share != null) ...[
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => Clipboard.setData(
                          ClipboardData(text: share.invitation.encode()),
                        ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(l10n.t('deviceShareCopy')),
                ),
                TextButton(
                  onPressed: busy ? null : onStop,
                  child: Text(l10n.t('deviceShareStop')),
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: busy ? null : onResume,
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: Text(l10n.t('deviceShareStart')),
                ),
              if (share == null && profile.automaticallyPrepares)
                TextButton(
                  onPressed: busy ? null : onStop,
                  child: Text(l10n.t('deviceSharePauseAuto')),
                ),
              IconButton(
                onPressed: busy ? null : onForget,
                tooltip: l10n.t('deviceShareForgetRule'),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 接收历史与当前连接共用记录；断开仅关闭连接，删除才移除保存的重连凭据。
class DeviceShareHistoryCard extends StatelessWidget {
  const DeviceShareHistoryCard({
    super.key,
    required this.entry,
    required this.connected,
    required this.busy,
    required this.onReconnect,
    required this.onDisconnect,
    required this.onForget,
  });
  final DeviceShareHistoryEntry entry;
  final JoinedDeviceShare? connected;
  final bool busy;
  final VoidCallback onReconnect, onDisconnect, onForget;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.invitation.name,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text('${entry.invitation.host}:${entry.invitation.port}'),
          Text(
            '${l10n.t('deviceShareLastConnected')}: ${_date(context, entry.lastConnectedAt)}',
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (connected == null)
                OutlinedButton.icon(
                  onPressed: busy ? null : onReconnect,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(l10n.t('deviceShareReconnect')),
                )
              else
                TextButton(
                  onPressed: busy ? null : onDisconnect,
                  child: Text(l10n.t('deviceShareLeave')),
                ),
              IconButton(
                onPressed: busy ? null : onForget,
                tooltip: l10n.t('deviceShareForgetHistory'),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _date(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  return '${MaterialLocalizations.of(context).formatShortDate(local)} '
      '${TimeOfDay.fromDateTime(local).format(context)}';
}
