import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ios/ios_control_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../widget/app_toast.dart';
import 'mirror_toolbar_button.dart';

/// iOS 投屏工具栏：deviceId 路由 WDA，两个截图回调复用窗口的复制/保存流程。
/// 示例：由 MirrorFloatingToolbar 在 iOS 分支传入当前设备与截图回调。
/// 仅显示已接入的能力，截图独立于 WDA，音量不附加 Android 长按行为。
class IosMirrorToolbar extends ConsumerWidget {
  const IosMirrorToolbar({
    super.key,
    required this.deviceId,
    required this.onScreenshot,
    required this.onSaveScreenshot,
  });

  final String deviceId;
  final VoidCallback onScreenshot;
  final VoidCallback onSaveScreenshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canControl = ref.watch(
      iosControlProvider(deviceId).select((s) => s.ready && !s.busy),
    );
    void perform(String action, [Map<String, dynamic> args = const {}]) {
      ref.read(iosControlProvider(deviceId).notifier).perform(action, args);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            MirrorToolbarButton(
              icon: const Icon(CupertinoIcons.lock),
              tooltip: context.l10n.t('iosLock'),
              onPressed: canControl ? () => perform('lock') : null,
            ),
            for (final button in [
              (CupertinoIcons.volume_up, 'volumeUp'),
              (CupertinoIcons.volume_down, 'volumeDown'),
              (Icons.radio_button_unchecked, 'home'),
            ])
              MirrorToolbarButton(
                icon: Icon(button.$1),
                tooltip: context.l10n.t(button.$2),
                onPressed: canControl
                    ? () => perform('button', {'name': button.$2})
                    : null,
              ),
            MirrorToolbarButton(
              icon: const Icon(Icons.text_fields),
              tooltip: context.l10n.t('getClipboardInput'),
              onPressed: canControl
                  ? () async {
                      final data = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (!context.mounted) return;
                      final text = data?.text;
                      if (text == null || text.isEmpty) {
                        AppToast.show(
                          context,
                          context.l10n.t('clipboardEmpty'),
                          type: AppToastType.warning,
                        );
                        return;
                      }
                      perform('text', {'text': text});
                    }
                  : null,
            ),
            MirrorToolbarButton(
              icon: const Icon(CupertinoIcons.camera),
              tooltip: context.l10n.t('screenshotTooltip'),
              onPressed: onScreenshot,
              onLongPress: onSaveScreenshot,
            ),
          ],
        ),
      ),
    );
  }
}
