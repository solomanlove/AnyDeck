import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../settings/app_settings_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/scrcpy/scrcpy_launch_options.dart';
import '../../../core/providers/app_providers.dart';

/// 启动外部原生投屏
Future<void> launchExternalMirror({
  required BuildContext context,
  required WidgetRef ref,
  required String deviceId,
  required String windowId,
  required bool isAlwaysOnTop,
}) async {
  // 1. 获取当前设置
  final settings = ref.read(appSettingsProvider);
  final bitrateMbps = (settings.mirrorVideoBitrate / 1000000).round();
  final options = ScrcpyLaunchOptions(
    maxSize: settings.mirrorMaxSize == 0 ? 1920 : settings.mirrorMaxSize,
    videoBitRate: '${bitrateMbps}M',
    alwaysOnTop: isAlwaysOnTop,
    noAudio: !settings.mirrorAudioEnabled,
  );

  // 2. 停止内嵌投屏
  await ref.read(activeEmbeddedMirrorProvider(deviceId).notifier).forceStop();

  // 3. 启动外部投屏
  try {
    final session = await ref
        .read(scrcpyServiceProvider)
        .start(deviceId: deviceId, options: options);
    ref.read(scrcpySessionsProvider.notifier).add(session);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('externalMirrorStarted')),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // 4. 关闭当前独立投屏窗口
    await windowManager.close();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n
                .t('startExternalMirrorFailed')
                .replaceAll('{error}', e.toString()),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// 显示投屏设置对话框
void showMirrorSettingsDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String deviceId,
  required String windowId,
  required bool isAlwaysOnTop,
}) {
  final settings = ref.read(appSettingsProvider);
  int selectedBitrate = settings.mirrorVideoBitrate;
  int selectedMaxSize = settings.mirrorMaxSize;

  final overview = ref.read(deviceOverviewProvider(deviceId)).asData?.value;
  int sdkVersion = 0;
  if (overview != null) {
    final match = RegExp(r'API\s+(\d+)').firstMatch(overview.androidVersion);
    if (match != null) {
      sdkVersion = int.tryParse(match.group(1) ?? '') ?? 0;
    }
  }
  final isAudioSupported = sdkVersion == 0 || sdkVersion >= 30;
  bool selectedAudio = isAudioSupported ? settings.mirrorAudioEnabled : false;

  showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardColor = isDark
              ? const Color(0xff1e1e1e)
              : const Color(0xffffffff);
          final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          );
          final dropdownStyle = Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontSize: 13);

          return AlertDialog(
            backgroundColor: cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Row(
              children: [
                Icon(
                  Icons.settings,
                  color: isDark ? Colors.white70 : Colors.black87,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.t('mirrorQualitySettings'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.t('videoBitrateLabel'), style: titleStyle),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    value: selectedBitrate,
                    isExpanded: true,
                    dropdownColor: cardColor,
                    style: dropdownStyle,
                    items: [
                      DropdownMenuItem(
                        value: 2000000,
                        child: Text(context.l10n.t('bitrate2Mbps')),
                      ),
                      DropdownMenuItem(
                        value: 4000000,
                        child: Text(context.l10n.t('bitrate4Mbps')),
                      ),
                      DropdownMenuItem(
                        value: 8000000,
                        child: Text(context.l10n.t('bitrate8Mbps')),
                      ),
                      DropdownMenuItem(
                        value: 16000000,
                        child: Text(context.l10n.t('bitrate16Mbps')),
                      ),
                      DropdownMenuItem(
                        value: 32000000,
                        child: Text(context.l10n.t('bitrate32Mbps')),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedBitrate = val);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(context.l10n.t('maxSizeLabel'), style: titleStyle),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    value: selectedMaxSize,
                    isExpanded: true,
                    dropdownColor: cardColor,
                    style: dropdownStyle,
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(context.l10n.t('sizeOriginal')),
                      ),
                      DropdownMenuItem(
                        value: 720,
                        child: const Text('720p (1280x720)'),
                      ),
                      DropdownMenuItem(
                        value: 1080,
                        child: const Text('1080p (1920x1080, 默认)'),
                      ),
                      DropdownMenuItem(
                        value: 1440,
                        child: const Text('1440p (2K / 2560x1440)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedMaxSize = val);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.t('audioForwardingLabel'),
                          style: titleStyle,
                        ),
                      ),
                      Switch(
                        value: selectedAudio,
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        onChanged: isAudioSupported
                            ? (val) {
                                setDialogState(() => selectedAudio = val);
                              }
                            : null,
                      ),
                    ],
                  ),
                  if (!isAudioSupported) ...[
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.t('audioForwardingNotSupported'),
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  // const SizedBox(height: 6),
                  // const Text(
                  //   '注意：当前内嵌投屏窗口因底层限制无法直接播放音频。如需使用音频转发到电脑播放，请使用外部原生投屏。',
                  //   style: TextStyle(
                  //     color: Colors.orangeAccent,
                  //     fontSize: 11,
                  //     fontWeight: FontWeight.w500,
                  //   ),
                  // ),
                  // const SizedBox(height: 12),
                  // OutlinedButton.icon(
                  //   style: OutlinedButton.styleFrom(
                  //     side: const BorderSide(color: Color(0xff2ec46b)),
                  //     foregroundColor: const Color(0xff2ec46b),
                  //     padding: const EdgeInsets.symmetric(
                  //       vertical: 8,
                  //       horizontal: 12,
                  //     ),
                  //     shape: RoundedRectangleBorder(
                  //       borderRadius: BorderRadius.circular(8),
                  //     ),
                  //   ),
                  //   icon: const Icon(Icons.open_in_new, size: 14),
                  //   label: const Text(
                  //     '启动外部原生投屏 (支持音频播放)',
                  //     style: TextStyle(fontSize: 12),
                  //   ),
                  //   onPressed: () {
                  //     Navigator.of(context).pop();
                  //     launchExternalMirror(
                  //       context: context,
                  //       ref: ref,
                  //       deviceId: deviceId,
                  //       windowId: windowId,
                  //       isAlwaysOnTop: isAlwaysOnTop,
                  //     );
                  //   },
                  // ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.t('mirrorSettingsNote'),
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  context.l10n.t('cancel'),
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  Navigator.of(context).pop();

                  // 保存配置
                  await ref
                      .read(appSettingsProvider.notifier)
                      .setMirrorVideoBitrate(selectedBitrate);
                  await ref
                      .read(appSettingsProvider.notifier)
                      .setMirrorMaxSize(selectedMaxSize);
                  await ref
                      .read(appSettingsProvider.notifier)
                      .setMirrorAudioEnabled(selectedAudio);

                  // 提示并重启
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.l10n.t('reloadingMirrorSettings'),
                        ),
                        duration: const Duration(milliseconds: 1500),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }

                  // 自动重连投屏
                  await ref
                      .read(activeEmbeddedMirrorProvider(deviceId).notifier)
                      .restartMirroring();
                },
                child: Text(
                  context.l10n.t('saveAndApply'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
