import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/scrcpy/scrcpy_keycode_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widget/app_toast.dart';
import 'mirror_toolbar_button.dart';
import 'mirror_window_controller.dart';

/// 将电脑剪贴板文本输入目标设备；controller 决定平台控制通道。
class MirrorClipboardInputButton extends ConsumerWidget {
  const MirrorClipboardInputButton({
    super.key,
    required this.deviceId,
    required this.controller,
  });

  final String deviceId;
  final MirrorWindowController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MirrorToolbarButton(
      icon: Text(
        'T',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).appColors.toolbarForeground,
        ),
      ),
      tooltip: context.l10n.t('getClipboardInput'),
      shortcut: MirrorShortcut.inputClipboard,
      onPressed: () async {
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        if (clipboardData != null &&
            clipboardData.text != null &&
            clipboardData.text!.isNotEmpty) {
          final text = clipboardData.text!;
          final success = controller.isIos
              ? await ref.read(iosControlProvider(deviceId).notifier).perform(
                  'text',
                  {'text': text},
                )
              : (controller.isHarmony
                    ? (await ref
                              .read(hdcServiceProvider)
                              .inputText(deviceId, text))
                          .isSuccess
                    : await ref
                          .read(embeddedScrcpyServiceProvider)
                          .sendControl(
                            deviceId: deviceId,
                            controlMessage:
                                ScrcpyKeycodeHelper.serializeTextEvent(text),
                          ));
          if (!success && context.mounted) {
            AppToast.show(
              context,
              context.l10n.t('sendClipboardFailed'),
              isError: true,
            );
          }
        } else {
          if (context.mounted) {
            AppToast.show(
              context,
              context.l10n.t('clipboardEmpty'),
              type: AppToastType.warning,
            );
          }
        }
      },
    );
  }
}
