import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/app_theme_colors.dart';
import '../../core/adb/discovered_device.dart';
import '../../core/adb/adb_result.dart';
import '../../core/providers/app_providers.dart';
import 'dashboard_snack.dart';
import 'device_power_actions.dart';
import 'remote_direction_pad.dart';

/// Android 与 HarmonyOS 共用的设备遥控器弹窗。
class RemoteControllerDialog extends ConsumerWidget {
  const RemoteControllerDialog({super.key, required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: theme.appColors.panelSurface,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10n.t('remoteController'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  color: Colors.grey,
                  hoverColor: Colors.grey.withValues(alpha: 0.1),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Outer grey frame resembling a real remote control
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).appColors.sunkenSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  // Row 1: Power, Vol Down, Vol Up
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildCircularButton(
                        icon: CupertinoIcons.power,
                        tooltip: context.l10n.t('power'),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        iconColor: const Color(
                          0xFFF38BA8,
                        ), // soft premium red for power
                        onPressed: () => _runAdb(
                          context,
                          ref,
                          pressPowerKeyAndResetScreenPower(
                            actions: actions,
                            deviceId: device.id,
                            screenPowerOffNotifier: ref.read(
                              screenPowerOffProvider(device.id).notifier,
                            ),
                          ),
                        ),
                      ),
                      _buildCircularButton(
                        icon: CupertinoIcons.volume_down,
                        tooltip: context.l10n.t('volumeDown'),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        iconColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                        onPressed: () => _runAdb(
                          context,
                          ref,
                          actions.volumeDown(device.id),
                        ),
                      ),
                      _buildCircularButton(
                        icon: CupertinoIcons.volume_up,
                        tooltip: context.l10n.t('volumeUp'),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        iconColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                        onPressed: () =>
                            _runAdb(context, ref, actions.volumeUp(device.id)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Row 2: D-Pad
                  RemoteDirectionPad(
                    onKey: (keyCode) => _runAdb(
                      context,
                      ref,
                      actions.keyEvent(device.id, keyCode),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Row 3: Home, Back (Capsule), Recents
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildCircularButton(
                        icon: CupertinoIcons.circle,
                        tooltip: context.l10n.t('home'),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        iconColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                        onPressed: () => _runAdb(
                          context,
                          ref,
                          actions.keyEvent(device.id, 3),
                        ),
                      ),
                      _buildCapsuleButton(
                        icon: Icons.arrow_left_rounded,
                        tooltip: context.l10n.t('back'),
                        color: Theme.of(context).colorScheme.outlineVariant,
                        iconColor: Theme.of(context).colorScheme.onSurface,
                        onPressed: () => _runAdb(
                          context,
                          ref,
                          actions.keyEvent(device.id, 4),
                        ),
                      ),
                      _buildCircularButton(
                        icon: CupertinoIcons.square,
                        tooltip: context.l10n.t('recentTasks'),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        iconColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                        onPressed: () => _runAdb(
                          context,
                          ref,
                          actions.keyEvent(device.id, 187),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required Color iconColor,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          hoverColor: Colors.black.withValues(alpha: 0.05),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: iconColor, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildCapsuleButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required Color iconColor,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(26),
          hoverColor: Colors.black.withValues(alpha: 0.05),
          child: SizedBox(
            width: 90,
            height: 52,
            child: Icon(icon, color: iconColor, size: 30),
          ),
        ),
      ),
    );
  }

  Future<void> _runAdb(
    BuildContext context,
    WidgetRef ref,
    Future<AdbResult> actionFuture,
  ) async {
    try {
      final res = await actionFuture;
      if (!res.isSuccess && context.mounted) {
        DashboardSnack.show(context, res.message, isError: true);
      }
    } catch (e) {
      if (context.mounted) {
        DashboardSnack.show(context, e.toString(), isError: true);
      }
    }
  }
}
