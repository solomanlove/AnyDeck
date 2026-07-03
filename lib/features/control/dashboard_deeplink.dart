part of '../dashboard_screen.dart';

/// 快捷跳转面板，用于通过 ADB 启动 Android 系统自带的常用设置页面及自定义 Deeplink 链接。
class _DeeplinkPanel extends ConsumerWidget {
  const _DeeplinkPanel({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);

    return _ActionCard(
      title: context.l10n.t('deeplink'),
      children: [
        // 开发者选项
        _ActionButton(
          icon: CupertinoIcons.device_desktop,
          label: context.l10n.t('deeplinkDeveloperOptions'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openDeveloperSettings(device.id),
          ),
        ),
        // 关于手机
        _ActionButton(
          icon: CupertinoIcons.info,
          label: context.l10n.t('deeplinkDeviceInfo'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openDeviceInfoSettings(device.id),
          ),
        ),
        // 语言设置
        _ActionButton(
          icon: CupertinoIcons.globe,
          label: context.l10n.t('deeplinkLanguages'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openLocaleSettings(device.id),
          ),
        ),
        // 系统设置
        _ActionButton(
          icon: CupertinoIcons.settings,
          label: context.l10n.t('deeplinkSettings'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.openMainSettings(device.id)),
        ),
        // Wi-Fi 设置
        _ActionButton(
          icon: CupertinoIcons.wifi,
          label: context.l10n.t('deeplinkWifi'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.openWifiSettings(device.id)),
        ),
        // 应用管理
        _ActionButton(
          icon: CupertinoIcons.square_grid_2x2,
          label: context.l10n.t('deeplinkApps'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openManageApplicationsSettings(device.id),
          ),
        ),
        // 工程模式
        _ActionButton(
          icon: CupertinoIcons.wrench,
          label: context.l10n.t('deeplinkTestingSettings'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openTestingSettings(device.id),
          ),
        ),
        // Google服务信息
        _ActionButton(
          icon: CupertinoIcons.info_circle,
          label: context.l10n.t('deeplinkGoogleSettings'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openGoogleSettings(device.id),
          ),
        ),
        // 自定义链接
        _ActionButton(
          icon: CupertinoIcons.link,
          label: context.l10n.t('deeplinkCustom'),
          onPressed: () => _showCustomDeeplinkDialog(context, ref, device.id),
        ),
      ],
    );
  }

  /// 弹出自定义 Deeplink 输入弹窗并通过 ADB am start 发送到设备。
  Future<void> _showCustomDeeplinkDialog(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('deeplinkCustomTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'https://... 或 myapp://...',
            labelText: context.l10n.t('deeplinkCustomHint'),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton.icon(
            icon: const Icon(CupertinoIcons.link),
            label: Text(context.l10n.t('send')),
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );

    controller.dispose();

    if (url == null || url.trim().isEmpty || !context.mounted) {
      return;
    }

    await _runAdbAction(
      context,
      ref,
      ref
          .read(deviceActionServiceProvider)
          .openCustomDeeplink(deviceId, url.trim()),
    );
  }
}
