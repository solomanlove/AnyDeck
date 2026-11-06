import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'mirror_clipboard_dialog.dart';
import 'mirror_toolbar_button.dart';

/// Android 投屏剪贴板入口；deviceId 为目标 ADB serial。
/// 点击后打开双栏剪贴板面板，关闭弹窗由 autoDispose 回收监听会话。
class MirrorClipboardButton extends StatelessWidget {
  const MirrorClipboardButton({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return MirrorToolbarButton(
      icon: Icon(
        Icons.content_paste,
        color: Theme.of(context).appColors.toolbarForeground,
      ),
      tooltip: context.l10n.t('clipboardTitle'),
      shortcut: MirrorShortcut.clipboard,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => MirrorClipboardDialog(
          deviceId: deviceId,
          deviceName: deviceName,
        ),
      ),
    );
  }
}
