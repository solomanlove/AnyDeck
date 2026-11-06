import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/apps/adb_package.dart';
import '../../../../core/scrcpy/fusion_mode_preference.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widget/app_toast.dart';
import '../mirror_toolbar_button.dart';

/// 标题栏前台应用入口，点击后等待应用投屏完成，并拦截重复操作。
///
/// [deviceId] 用于读取融合开关，[package] 提供图标和应用名称；
/// [onOpen] 复用应用投屏路由，[onQuickActions] 响应长按和右键。
/// 用法：作为标题栏的独立操作项，放在窗口拖拽区域之外。
class MirrorForegroundAppButton extends ConsumerStatefulWidget {
  const MirrorForegroundAppButton({
    super.key,
    required this.deviceId,
    required this.package,
    required this.onOpen,
    required this.onQuickActions,
  });

  final String deviceId;
  final AdbPackage package;
  final Future<void> Function() onOpen;
  final VoidCallback onQuickActions;

  @override
  ConsumerState<MirrorForegroundAppButton> createState() =>
      _MirrorForegroundAppButtonState();
}

class _MirrorForegroundAppButtonState
    extends ConsumerState<MirrorForegroundAppButton> {
  bool _isOpening = false;

  Future<void> _open() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    try {
      await widget.onOpen();
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          context.l10n
              .t('appMirroringFailed')
              .replaceAll('{name}', widget.package.displayName)
              .replaceAll('{error}', error.toString()),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(
      deviceFusionModeProvider(
        widget.deviceId,
      ).select((value) => value.asData?.value.state),
    );
    final title = context.l10n.t(
      mode == FusionModeState.enabled
          ? 'fusionAppTooltip'
          : 'primaryAppTooltip',
    );
    final iconPath = widget.package.iconLocalPath;
    final fallback = Icon(
      CupertinoIcons.app,
      size: 16,
      color: Theme.of(context).appColors.toolbarForeground,
    );

    return SizedBox.square(
      dimension: 28,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTap: _isOpening ? null : widget.onQuickActions,
        child: MirrorToolbarButton(
          icon: iconPath != null && File(iconPath).existsSync()
              ? Image.file(
                  File(iconPath),
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => fallback,
                )
              : fallback,
          tooltip: _isOpening
              ? context.l10n.t('startingMirrorService')
              : '$title · ${context.l10n.t('fusionQuickActionsHint')}',
          isLoading: _isOpening,
          onPressed: _open,
          onLongPress: widget.onQuickActions,
        ),
      ),
    );
  }
}
