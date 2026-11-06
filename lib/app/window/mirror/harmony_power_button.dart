import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widget/app_toast.dart';
import 'mirror_toolbar_button.dart';

/// 鸿蒙投屏电源入口：明确选择唤醒或息屏，避免本地亮灭状态与实体按键不同步。
/// [deviceId] 为当前投屏的 HDC 设备标识；命令执行期间禁止重复点击。
class HarmonyPowerButton extends ConsumerStatefulWidget {
  const HarmonyPowerButton({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<HarmonyPowerButton> createState() => _HarmonyPowerButtonState();
}

class _HarmonyPowerButtonState extends ConsumerState<HarmonyPowerButton> {
  bool _busy = false;

  Future<void> _openMenu() async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      button.localToGlobal(Offset.zero, ancestor: overlay) & button.size,
      Offset.zero & overlay.size,
    );
    final powerOn = await showMenu<bool>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: true,
          child: ListTile(
            leading: const Icon(CupertinoIcons.sun_max),
            title: Text(context.l10n.t('mirrorWakeScreen')),
          ),
        ),
        PopupMenuItem(
          value: false,
          child: ListTile(
            leading: const Icon(CupertinoIcons.moon_fill),
            title: Text(context.l10n.t('mirrorSleepScreen')),
          ),
        ),
      ],
    );
    if (powerOn == null || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(hdcServiceProvider).setScreenPower(
        widget.deviceId,
        powerOn: powerOn,
      );
      if (mounted && !result.isSuccess) {
        AppToast.show(context, result.message, isError: true);
      }
    } catch (error) {
      if (mounted) AppToast.show(context, '$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MirrorToolbarButton(
    icon: Icon(
      CupertinoIcons.power,
      color: Theme.of(context).appColors.toolbarForeground,
    ),
    tooltip: context.l10n.t('power'),
    shortcut: MirrorShortcut.power,
    isLoading: _busy,
    onPressed: _openMenu,
  );
}
