import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ios/ios_control_provider.dart';
import '../../../core/ios/ios_mirror_service.dart';
import '../../../features/ios/widgets/ios_control_bar.dart';
import '../../l10n/app_localizations.dart';
import '../../widget/app_toast.dart';
import 'mirror_toolbar_button.dart';

/// iOS 投屏工具栏：deviceId 路由 WDA，两个截图回调复用窗口的复制/保存流程。
/// 示例：由 MirrorFloatingToolbar 在 iOS 分支传入当前设备与截图回调。
/// 仅显示已接入的能力，截图独立于 WDA，音量不附加 Android 长按行为。
class IosMirrorToolbar extends ConsumerStatefulWidget {
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
  ConsumerState<IosMirrorToolbar> createState() => _IosMirrorToolbarState();
}

class _IosMirrorToolbarState extends ConsumerState<IosMirrorToolbar> {
  bool _showingError = false;

  Future<void> _showError(String error) async {
    if (_showingError || !mounted || error.isEmpty) return;
    _showingError = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.t('error')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
          child: SingleChildScrollView(
            child: SelectableText(iosControlErrorText(dialogContext, error)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.l10n.t('close')),
          ),
        ],
      ),
    );
    _showingError = false;
  }

  @override
  Widget build(BuildContext context) {
    final control = ref.watch(
      iosControlProvider(
        widget.deviceId,
      ).select((state) => (ready: state.ready, busy: state.busy)),
    );
    final fps = ref.watch(
      iosUsbFrameProvider(
        widget.deviceId,
      ).select((data) => (data['fps'] as num?)?.toStringAsFixed(1) ?? '-'),
    );
    ref.listen<String?>(
      iosControlProvider(widget.deviceId).select((state) => state.error),
      (_, error) => _showError(error ?? ''),
    );
    ref.listen<String>(
      iosUsbFrameProvider(
        widget.deviceId,
      ).select((data) => '${data['error'] ?? ''}'),
      (_, error) => _showError(error),
    );
    final canControl = control.ready && !control.busy;
    void perform(String action, [Map<String, dynamic> args = const {}]) {
      ref
          .read(iosControlProvider(widget.deviceId).notifier)
          .perform(action, args);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Row(
        children: [
          Expanded(
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
                    onPressed: widget.onScreenshot,
                    onLongPress: widget.onSaveScreenshot,
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    key: const ValueKey('ios-control-toggle'),
                    onPressed: () => perform(
                      control.ready || control.busy ? 'stop' : 'start',
                    ),
                    icon: control.busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            control.ready
                                ? Icons.mouse
                                : Icons.touch_app_outlined,
                            size: 16,
                          ),
                    label: Text(
                      context.l10n.t(
                        control.busy
                            ? 'iosCancelControl'
                            : control.ready
                            ? 'iosStopControl'
                            : 'iosStartControl',
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$fps FPS',
            key: const ValueKey('ios-mirror-fps'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
