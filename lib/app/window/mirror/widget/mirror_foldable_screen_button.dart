import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foldable/foldable_screen_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widget/app_toast.dart';
import '../mirror_toolbar_button.dart';

/// Android 整机投屏的内外屏切换入口，未确认当前屏幕时不占工具栏空间。
///
/// [deviceId] 是当前在线的 ADB transport；父工具栏负责排除其他平台和 App 副屏。
/// 点击切到另一块屏，长按恢复自动；设备探测与请求回收由 Provider 管理。
class MirrorFoldableScreenButton extends ConsumerWidget {
  const MirrorFoldableScreenButton({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(foldableScreenProvider(deviceId));
    final screen = state.snapshot?.currentScreen;
    if (screen == null) return const SizedBox.shrink();

    final automatic =
        state.mode == FoldableScreenMode.automatic &&
        state.snapshot?.hasOverride != true;
    final current = context.l10n.t(
      screen == FoldableScreen.inner
          ? 'foldableScreenInner'
          : 'foldableScreenOuter',
    );
    final target = context.l10n.t(
      screen == FoldableScreen.inner
          ? 'foldableScreenOuter'
          : 'foldableScreenInner',
    );
    final tooltip = state.isBusy
        ? context.l10n.t('foldableScreenSwitching')
        : context.l10n
              .t(
                automatic
                    ? 'foldableScreenAutomaticTooltip'
                    : 'foldableScreenManualTooltip',
              )
              .replaceAll('{current}', current)
              .replaceAll('{target}', target);
    final color = Theme.of(context).appColors.toolbarForeground;

    return MirrorToolbarButton(
      key: const ValueKey('mirror-foldable-screen-toggle'),
      icon: screen == FoldableScreen.inner
          ? RotatedBox(
              quarterTurns: 1,
              child: Icon(
                Icons.tablet_android_outlined,
                key: const ValueKey('mirror-foldable-inner-icon'),
                color: color,
                size: 16,
              ),
            )
          : Icon(
              Icons.smartphone,
              key: const ValueKey('mirror-foldable-outer-icon'),
              color: color,
              size: 16,
            ),
      badge: automatic && !state.isBusy
          ? Text(
              context.l10n.t('foldableScreenAutomaticBadge'),
              key: const ValueKey('mirror-foldable-automatic-badge'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
      tooltip: state.error == null || state.isBusy
          ? tooltip
          : '$tooltip\n${context.l10n.t(_errorKey(state.error!))}',
      isLoading: state.isBusy,
      onPressed: () => _perform(context, ref, restoreAutomatic: false),
      onLongPress: () => _perform(context, ref, restoreAutomatic: true),
    );
  }

  /// 等待设备状态回读完成后反馈结果，窗口关闭后的迟到结果不再显示提示。
  Future<void> _perform(
    BuildContext context,
    WidgetRef ref, {
    required bool restoreAutomatic,
  }) async {
    final controller = ref.read(foldableScreenProvider(deviceId).notifier);
    final error = await (restoreAutomatic
        ? controller.restoreAutomatic()
        : controller.toggle());
    if (!context.mounted) return;
    if (error != null) {
      AppToast.show(context, context.l10n.t(_errorKey(error)), isError: true);
    } else if (restoreAutomatic) {
      AppToast.show(context, context.l10n.t('foldableScreenAutomaticRestored'));
    }
  }
}

/// 将设备层错误映射到统一文案，避免向用户暴露原始 ADB 输出。
String _errorKey(FoldableScreenError error) => switch (error) {
  FoldableScreenError.unsupported => 'foldableScreenUnavailable',
  FoldableScreenError.unavailable => 'foldableScreenUnavailable',
  FoldableScreenError.timeout => 'foldableScreenTimeout',
  FoldableScreenError.failed => 'foldableScreenFailed',
  FoldableScreenError.busyExternal => 'foldableScreenBusyExternal',
  FoldableScreenError.screenOff => 'foldableScreenOff',
  FoldableScreenError.recording => 'foldableScreenRecording',
};
