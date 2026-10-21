import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../../features/apps/widgets/device_clipboard_view.dart';
import 'mirror_toolbar_button.dart';

/// Android 投屏剪贴板入口；deviceId 为目标 ADB serial。
/// 点击后复用手机剪贴板面板，关闭弹窗由 autoDispose 回收监听会话。
class MirrorClipboardButton extends StatelessWidget {
  const MirrorClipboardButton({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return MirrorToolbarButton(
      icon: Icon(
        Icons.content_paste,
        color: Theme.of(context).appColors.toolbarForeground,
      ),
      tooltip: context.l10n.t('clipboardTitle'),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.t('clipboardTitle')),
          content: SizedBox(
            width: 640,
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: DeviceClipboardView(deviceId: deviceId),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.t('close')),
            ),
          ],
        ),
      ),
    );
  }
}
