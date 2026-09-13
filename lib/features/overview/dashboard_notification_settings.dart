part of '../dashboard_screen.dart';

/// 桌面主面板设置页：macOS 本地通知与消息设置卡片组件扩展。
extension _SettingsTabNotificationSection on _SettingsTab {
  Widget _buildNotificationSectionCard(
    BuildContext context,
    WidgetRef ref,
    Color brandGreen,
  ) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final bridge = ref.read(macNotificationBridgeProvider);

    return _buildSectionCard(
      context,
      title: context.l10n.t('notificationSettingsTitle'),
      icon: CupertinoIcons.bell,
      children: [
        // 1. Android 设备连接桌面通知
        _buildSettingRow(
          context,
          label: context.l10n.t('deviceConnectNotification'),
          subtitle: context.l10n.t('deviceConnectNotificationDesc'),
          child: Switch.adaptive(
            activeThumbColor: brandGreen,
            activeTrackColor: brandGreen.withValues(alpha: 0.5),
            value: settings.deviceConnectNotification,
            onChanged: (val) async {
              if (val && Platform.isMacOS) {
                final status = await bridge.getAuthorizationStatus();
                if (status == 'notDetermined') {
                  final granted = await bridge.requestAuthorization();
                  if (!granted && context.mounted) {
                    _showNotificationPermissionNotice(context, bridge);
                  }
                } else if (status == 'denied' && context.mounted) {
                  _showNotificationPermissionNotice(context, bridge);
                }
              }
              await controller.setDeviceConnectNotification(val);
            },
          ),
        ),
        const Divider(height: 24),

        // 2. 消息通知正文预览
        _buildSettingRow(
          context,
          label: context.l10n.t('notificationBodyPreview'),
          subtitle: context.l10n.t('notificationBodyPreviewDesc'),
          child: Switch.adaptive(
            activeThumbColor: brandGreen,
            activeTrackColor: brandGreen.withValues(alpha: 0.5),
            value: settings.notificationBodyPreview,
            onChanged: (val) => controller.setNotificationBodyPreview(val),
          ),
        ),
        const Divider(height: 24),

        // 3. 系统级通知权限状态与快捷引导
        _buildSettingRow(
          context,
          label: context.l10n.t('notificationPermission'),
          subtitle: context.l10n.t('notificationPermissionDesc'),
          child: FutureBuilder<String>(
            future: bridge.getAuthorizationStatus(),
            builder: (context, snapshot) {
              final status = snapshot.data ?? 'notDetermined';
              if (status == 'authorized') {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Color(0xff09c47c),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.t('notificationPermissionGranted'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xff09c47c),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              }

              final isDenied = status == 'denied';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isDenied
                        ? CupertinoIcons.exclamationmark_circle
                        : CupertinoIcons.question_circle,
                    color: isDenied ? Colors.orange : Colors.grey,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: brandGreen,
                      side: BorderSide(color: brandGreen),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      if (isDenied) {
                        await bridge.openNotificationSettings();
                      } else {
                        final granted = await bridge.requestAuthorization();
                        if (!granted && context.mounted) {
                          _showNotificationPermissionNotice(context, bridge);
                        }
                      }
                    },
                    child: Text(
                      isDenied
                          ? context.l10n.t('openSystemSettings')
                          : context.l10n.t('requestPermission'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _showNotificationPermissionNotice(
    BuildContext context,
    MacNotificationBridge bridge,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.t('notificationPermissionDenied')),
        action: SnackBarAction(
          label: context.l10n.t('openSystemSettings'),
          textColor: const Color(0xff09c47c),
          onPressed: () => bridge.openNotificationSettings(),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
