import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/scrcpy/scrcpy_keycode_helper.dart';
import '../../../features/apps/controller/device_auxiliary_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme_sizes.dart';
import 'controller/mirror_clipboard_sync_controller.dart';

/// Android 投屏窗口的双栏文本剪贴板面板；关闭时释放监听会话与电脑轮询。
///
/// [deviceId] 是当前投屏 ADB serial；[deviceName] 用于右栏标题和粘贴按钮。
class MirrorClipboardDialog extends ConsumerStatefulWidget {
  const MirrorClipboardDialog({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  @override
  ConsumerState<MirrorClipboardDialog> createState() =>
      _MirrorClipboardDialogState();
}

class _MirrorClipboardDialogState extends ConsumerState<MirrorClipboardDialog> {
  late final MirrorClipboardSyncController _sync;
  late final AuxiliaryKey _key;

  @override
  void initState() {
    super.initState();
    _key = (deviceId: widget.deviceId, microphone: false);
    _sync = MirrorClipboardSyncController(
      readHost: () async =>
          (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      writeHost: (text) => Clipboard.setData(ClipboardData(text: text)),
      writeDevice: (text, {required paste}) => ref
          .read(embeddedScrcpyServiceProvider)
          .sendControl(
            deviceId: widget.deviceId,
            controlMessage: ScrcpyKeycodeHelper.serializeSetClipboard(
              text,
              paste: paste,
            ),
          ),
    )..addListener(_onSyncChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _sync.start();
      if (mounted) {
        await ref.read(deviceAuxiliaryProvider(_key).notifier).start();
      }
    });
  }

  void _onSyncChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sync.removeListener(_onSyncChanged);
    _sync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceState = ref.watch(deviceAuxiliaryProvider(_key));
    ref.listen(deviceAuxiliaryProvider(_key), (previous, next) {
      final text = next.text;
      if (text != null && text != previous?.text) _sync.onDeviceText(text);
    });
    final colors = Theme.of(context).colorScheme;
    final hostName = Platform.isMacOS
        ? context.l10n.t('mirrorClipboardMac')
        : context.l10n.t('mirrorClipboardComputer');
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 24).clamp(0.0, 940.0);
    final height = (screen.height - 24).clamp(0.0, 610.0);
    final errorKey =
        _sync.errorKey ?? (deviceState.failed ? deviceState.messageKey : null);

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: _sync.autoSync,
                    onChanged: (value) => _sync.setAutoSync(value ?? false),
                  ),
                  Text(
                    context.l10n.t('mirrorClipboardAutoSync'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: context.l10n.t('close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (errorKey != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.t(errorKey),
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                    if (deviceState.failed)
                      TextButton(
                        onPressed: deviceState.busy
                            ? null
                            : () => ref
                                  .read(deviceAuxiliaryProvider(_key).notifier)
                                  .start(),
                        child: Text(context.l10n.t('mirrorClipboardRetry')),
                      ),
                  ],
                ),
              if (deviceState.busy) const LinearProgressIndicator(),
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 600;
                    final hostPane = _ClipboardPane(
                      title: context.l10n
                          .t('mirrorClipboardHostTitle')
                          .replaceAll('{host}', hostName),
                      text: _sync.hostText,
                      emptyMessage: context.l10n.t('mirrorClipboardHostEmpty'),
                      buttonLabel: context.l10n
                          .t('mirrorClipboardPasteTo')
                          .replaceAll('{device}', widget.deviceName),
                      busy: _sync.sendingDevice,
                      onPressed: _sync.hostText?.isNotEmpty == true
                          ? _sync.pasteToDevice
                          : null,
                    );
                    final devicePane = _ClipboardPane(
                      title: context.l10n
                          .t('mirrorClipboardDeviceTitle')
                          .replaceAll('{device}', widget.deviceName),
                      text: _sync.deviceText,
                      emptyMessage: context.l10n.t(
                        'mirrorClipboardDeviceEmpty',
                      ),
                      buttonLabel: context.l10n
                          .t('mirrorClipboardCopyToHost')
                          .replaceAll('{host}', hostName),
                      busy: _sync.copyingHost,
                      onPressed: _sync.deviceText?.isNotEmpty == true
                          ? _sync.copyToHost
                          : null,
                    );
                    if (narrow) {
                      return Column(
                        children: [
                          Expanded(child: hostPane),
                          const SizedBox(height: 14),
                          Expanded(child: devicePane),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: hostPane),
                        const SizedBox(width: 24),
                        Expanded(child: devicePane),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标题、可选择文本区域与单向操作按钮共用同一布局。
class _ClipboardPane extends StatelessWidget {
  const _ClipboardPane({
    required this.title,
    required this.text,
    required this.emptyMessage,
    required this.buttonLabel,
    required this.busy,
    required this.onPressed,
  });

  final String title;
  final String? text;
  final String emptyMessage;
  final String buttonLabel;
  final bool busy;
  final Future<bool> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: AppThemeSizes.radiusLarge,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: text == null || text!.isEmpty
                ? Center(
                    child: Text(
                      emptyMessage,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText(text!),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy || onPressed == null ? null : () => onPressed!(),
          child: Text(buttonLabel),
        ),
      ],
    );
  }
}
