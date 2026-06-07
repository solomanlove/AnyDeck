import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../settings/app_settings_controller.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/scrcpy/scrcpy_launch_options.dart';
import '../../../core/providers/app_providers.dart';

/// 启动外部原生投屏
Future<void> launchExternalMirror({
  required BuildContext context,
  required WidgetRef ref,
  required String deviceId,
  required int windowId,
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
          content: const Text('已启动系统原生投屏，音频已同步转发到电脑播放'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // 4. 关闭当前独立投屏窗口
    await WindowController.fromWindowId(windowId).close();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('启动外部原生投屏失败: $e'),
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
  required int windowId,
  required bool isAlwaysOnTop,
}) {
  final settings = ref.read(appSettingsProvider);
  int selectedBitrate = settings.mirrorVideoBitrate;
  int selectedMaxSize = settings.mirrorMaxSize;
  bool selectedAudio = settings.mirrorAudioEnabled;

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
          final titleStyle = Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);

          return AlertDialog(
            backgroundColor: cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.settings,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                const SizedBox(width: 8),
                const Text('投屏画质设置'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('视频比特率 (Video Bitrate)', style: titleStyle),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    value: selectedBitrate,
                    isExpanded: true,
                    dropdownColor: cardColor,
                    items: const [
                      DropdownMenuItem(
                        value: 2000000,
                        child: Text('2 Mbps (极低/流畅)'),
                      ),
                      DropdownMenuItem(
                        value: 4000000,
                        child: Text('4 Mbps (低)'),
                      ),
                      DropdownMenuItem(
                        value: 8000000,
                        child: Text('8 Mbps (默认/推荐)'),
                      ),
                      DropdownMenuItem(
                        value: 16000000,
                        child: Text('16 Mbps (超清)'),
                      ),
                      DropdownMenuItem(
                        value: 32000000,
                        child: Text('32 Mbps (极清/高带宽)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedBitrate = val);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  Text('最佳尺寸 (Max Size / 分辨率)', style: titleStyle),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    value: selectedMaxSize,
                    isExpanded: true,
                    dropdownColor: cardColor,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('原始大小 (无限制)')),
                      DropdownMenuItem(
                        value: 720,
                        child: Text('720p (1280x720)'),
                      ),
                      DropdownMenuItem(
                        value: 1080,
                        child: Text('1080p (1920x1080, 默认)'),
                      ),
                      DropdownMenuItem(
                        value: 1440,
                        child: Text('1440p (2K / 2560x1440)'),
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
                      Text('音频转发 (Audio Forwarding)', style: titleStyle),
                      Switch(
                        value: selectedAudio,
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        onChanged: (val) {
                          setDialogState(() => selectedAudio = val);
                        },
                      ),
                    ],
                  ),
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
                  const Text(
                    '注：修改设置后保存，投屏服务将自动重启以应用新画质。',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
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
                      const SnackBar(
                        content: Text('正在重载投屏画质设置...'),
                        duration: Duration(milliseconds: 1500),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }

                  // 自动重连投屏
                  await ref
                      .read(activeEmbeddedMirrorProvider(deviceId).notifier)
                      .restartMirroring();
                },
                child: const Text('保存并应用'),
              ),
            ],
          );
        },
      );
    },
  );
}
