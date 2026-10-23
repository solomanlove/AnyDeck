import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/settings/app_settings_controller.dart';
import '../../app/widget/app_toast.dart';
import '../../core/dlna/dlna_renderer_service.dart';

/// 主窗口 DLNA 接收开关；Android 视频 App 可在同一局域网发现电脑。
class DlnaToolbarButton extends ConsumerStatefulWidget {
  const DlnaToolbarButton({super.key, required this.iconColor});

  final Color iconColor;

  @override
  ConsumerState<DlnaToolbarButton> createState() => _DlnaToolbarButtonState();
}

class _DlnaToolbarButtonState extends ConsumerState<DlnaToolbarButton> {
  final _service = DlnaRendererService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (_service.isBusy) return;
    try {
      if (_service.isRunning) {
        await _service.stop();
      } else {
        await _service.setServerName(ref.read(appSettingsProvider).dlnaServerName);
        await _service.start();
      }
      if (mounted) {
        AppToast.show(
          context,
          context.l10n
              .t(_service.isRunning ? 'dlnaStarted' : 'dlnaStopped')
              .replaceAll('{name}', _service.serverName),
        );
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          context.l10n.t('dlnaFailed').replaceAll('{error}', '$error'),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return const SizedBox.shrink();
    return IconButton(
      tooltip: context.l10n.t(_service.isRunning ? 'dlnaStop' : 'dlnaStart'),
      icon: const Icon(Icons.cast_connected_rounded),
      iconSize: 30,
      color: _service.isRunning
          ? Theme.of(context).colorScheme.primary
          : widget.iconColor,
      onPressed: _service.isBusy ? null : _toggle,
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
