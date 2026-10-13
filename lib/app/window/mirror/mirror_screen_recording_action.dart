import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/screen_record_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../widget/app_toast.dart';

/// 保留 Android/HarmonyOS 原有录屏启停、导出和清理流程；iOS 工具栏不调用。
Future<void> toggleMirrorScreenRecording(
  BuildContext context,
  WidgetRef ref,
  String deviceId,
  {int? displayId}
) async {
  final recordState = ref.read(screenRecordProvider(deviceId));
  final recordNotifier = ref.read(screenRecordProvider(deviceId).notifier);

  if (recordState.isRecording) {
    try {
      final recordResult = await recordNotifier.stop();
      if (recordResult == null) return;

      if (recordResult.startsWith('local:')) {
        final localSavePath = recordResult.substring(6);
        if (context.mounted) {
          AppToast.show(
            context,
            context.l10n.t('recordSuccess').replaceAll('{path}', localSavePath),
          );
        }
        return;
      }

      final remotePath = recordResult;
      final settings = ref.read(appSettingsProvider);
      final hostPlatform = ref.read(hostPlatformServiceProvider);
      final localSavePath = hostPlatform.generateRecordPath(
        settings.screenshotSavePath,
        deviceId,
      );
      final file = File(localSavePath);
      await file.parent.create(recursive: true);

      final pullResult = await ref
          .read(fileManagerServiceProvider)
          .pull(deviceId, remotePath, localSavePath);

      if (pullResult.isSuccess) {
        if (context.mounted) {
          AppToast.show(
            context,
            context.l10n.t('recordSuccess').replaceAll('{path}', localSavePath),
          );
        }
      } else {
        throw Exception(
          pullResult.stderr.isNotEmpty
              ? pullResult.stderr
              : 'File transfer failed',
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(
          context,
          context.l10n.t('recordFailed').replaceAll('{error}', '$e'),
          isError: true,
        );
      }
    } finally {
      try {
        await ref
            .read(fileManagerServiceProvider)
            .delete(deviceId, '/sdcard/adb_screenrecord_temp.mp4');
      } catch (_) {}
    }
  } else {
    try {
      await recordNotifier.start(displayId: displayId);
    } catch (e) {
      if (context.mounted) {
        AppToast.show(
          context,
          context.l10n.t('recordFailed').replaceAll('{error}', '$e'),
          isError: true,
        );
      }
    }
  }
}
