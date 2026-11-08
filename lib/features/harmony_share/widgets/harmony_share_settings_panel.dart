import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';

/// 互传设置展示面板；directory 为空表示 Downloads，permission 为系统权限原值。
/// saving/busy 控制写入与收发互斥；所有回调由主窗口设置控制器处理。
/// permissionRequestFailed 仅调整失败后的操作入口，不改写系统返回的 permission。
/// 用法：放入 AlertDialog.content，并传入当前 AppSettings 与操作回调。
class HarmonyShareSettingsPanel extends StatelessWidget {
  const HarmonyShareSettingsPanel({
    super.key,
    required this.notifications,
    required this.directory,
    required this.permission,
    required this.saving,
    required this.busy,
    required this.onNotifications,
    required this.onChooseDirectory,
    required this.onResetDirectory,
    required this.onPermission,
    required this.onRefreshPermission,
    this.deliveryFailed = false,
    this.permissionRequestFailed = false,
    this.errorKey,
    this.nameEditor,
  });

  final bool notifications;
  final String directory;
  final String? permission;
  final bool saving;
  final bool busy;
  final ValueChanged<bool> onNotifications;
  final VoidCallback onChooseDirectory;
  final VoidCallback onResetDirectory;
  final VoidCallback onPermission;
  final VoidCallback onRefreshPermission;
  final bool deliveryFailed;
  final bool permissionRequestFailed;
  final String? errorKey;
  /// 可选名称编辑器，状态与保存逻辑由主窗口持有。
  final Widget? nameEditor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final authorized =
        permission == 'authorized' || permission == 'provisional';
    final permissionKey = permission == null
        ? 'harmonySharePermissionChecking'
        : authorized
        ? 'notificationPermissionGranted'
        : permission == 'denied'
        ? 'notificationPermissionDenied'
        : permission == 'notDetermined'
        ? 'harmonySharePermissionNeeded'
        : 'harmonySharePermissionUnknown';
    return SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (nameEditor != null) ...[
            nameEditor!,
            const Divider(),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.t('harmonyShareNotifications')),
            subtitle: Text(l10n.t('harmonyShareNotificationsHint')),
            value: notifications,
            onChanged: saving ? null : onNotifications,
          ),
          const SizedBox(height: 8),
          Text(l10n.t(permissionKey)),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: saving || permission == null ? null : onPermission,
                child: Text(
                  l10n.t(
                    permission == 'notDetermined' && !permissionRequestFailed
                        ? 'requestPermission'
                        : 'openSystemSettings',
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.t('harmonySharePermissionRefresh'),
                onPressed: saving ? null : onRefreshPermission,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (deliveryFailed)
            Text(
              l10n.t('harmonyShareNotificationFailed'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            l10n.t('harmonyShareReceiveDirectory'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SelectableText(
            directory.isEmpty
                ? l10n.t('harmonyShareDefaultDirectory')
                : directory,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.t('harmonyShareReceiveDirectoryHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: saving || busy ? null : onChooseDirectory,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(l10n.t('harmonyShareChooseDirectory')),
              ),
              TextButton(
                onPressed: saving || busy || directory.isEmpty
                    ? null
                    : onResetDirectory,
                child: Text(l10n.t('harmonyShareResetDirectory')),
              ),
            ],
          ),
          if (busy) Text(l10n.t('harmonyShareSettingsBusy')),
          if (saving) const LinearProgressIndicator(),
          if (errorKey != null) ...[
            const SizedBox(height: 12),
            Text(
              l10n.t(errorKey!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
