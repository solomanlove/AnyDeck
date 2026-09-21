import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/app_toast.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/providers/app_providers.dart';
import '../controller/audio_forward_controller.dart';

/// 纯音频转发（无画面）操作按钮。
///
/// 用途：
/// 提供在控制 Tab 下一键启停后台纯音频转发的功能。无需开启投屏窗口即可在宿主机扬声器收听 Android 设备音频。
///
/// 参数：
/// - [device]：目标 ADB 设备实体对象。
///
/// 用法示例：
/// ```dart
/// AudioForwardButton(device: device)
/// ```
class AudioForwardButton extends ConsumerWidget {
  /// 创建纯音频转发操作按钮实例
  const AudioForwardButton({
    super.key,
    required this.device,
  });

  /// 目标设备对象
  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioForwardControllerProvider(device.id));
    final controller = ref.read(audioForwardControllerProvider(device.id).notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isActive = state.isActive;
    final isStarting = state.isStarting;

    final labelText = context.l10n.t('audioOnlyMirror');
    final tooltipText = context.l10n.t('audioOnlyMirrorTooltip');

    Widget button;
    if (isActive) {
      button = FilledButton.icon(
        icon: const Icon(CupertinoIcons.speaker_2_fill, size: 18),
        label: Text(labelText),
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
        onPressed: () async {
          await controller.stop();
          if (context.mounted) {
            AppToast.show(context, context.l10n.t('audioOnlyStopped'));
          }
        },
      );
    } else {
      button = OutlinedButton.icon(
        icon: isStarting
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              )
            : const Icon(CupertinoIcons.speaker_2, size: 18),
        label: Text(labelText),
        onPressed: isStarting
            ? null
            : () async {
                // 1. 在线检测
                if (!device.isOnline) {
                  AppToast.show(
                    context,
                    context.l10n.t('selectDeviceToMirror'),
                    isError: true,
                  );
                  return;
                }

                // 2. Android 门槛检测 (Android 11+ / API 30+)
                final sdkVersion =
                    ref.read(deviceSdkVersionProvider(device.id)) ?? 0;
                if (sdkVersion > 0 && sdkVersion < 30) {
                  AppToast.show(
                    context,
                    context.l10n.t('audioForwardingNotSupported'),
                    isError: true,
                  );
                  return;
                }

                // 3. 执行启动
                final success = await controller.start();
                if (!context.mounted) return;

                if (success) {
                  AppToast.show(context, context.l10n.t('audioOnlyStarted'));
                } else {
                  final err = ref.read(audioForwardControllerProvider(device.id)).errorMessage;
                  if (err == 'unsupported') {
                    AppToast.show(
                      context,
                      context.l10n.t('audioForwardingNotSupported'),
                      isError: true,
                    );
                  } else {
                    AppToast.show(
                      context,
                      '${context.l10n.t('audioOnlyFailed')}${err != null ? ': $err' : ''}',
                      isError: true,
                    );
                  }
                }
              },
      );
    }

    return Tooltip(
      message: tooltipText,
      child: button,
    );
  }
}
