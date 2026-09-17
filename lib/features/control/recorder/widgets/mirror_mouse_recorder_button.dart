import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/window/mirror/mirror_floating_toolbar.dart';
import '../controller/mouse_track_recorder_controller.dart';

/// 投屏悬浮工具栏中的鼠标操作路径录制与回放控制器按钮组。
///
/// 用于在投屏画面上录制鼠标移动、点击、滑动及滚轮轨迹，并在需要时一键重放执行。
///
/// 参数说明：
/// - [deviceId]: 目标投屏设备的唯一标识符
/// - [isDark]: 当前主题是否为暗黑模式
///
/// 用法示例：
/// ```dart
/// MirrorMouseRecorderButton(
///   deviceId: widget.deviceId,
///   isDark: isDark,
/// )
/// ```
class MirrorMouseRecorderButton extends ConsumerWidget {
  const MirrorMouseRecorderButton({
    super.key,
    required this.deviceId,
    required this.isDark,
  });

  /// 目标投屏设备 ID
  final String deviceId;

  /// 是否为暗色主题
  final bool isDark;

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mouseTrackRecorderProvider(deviceId));
    final notifier = ref.read(mouseTrackRecorderProvider(deviceId).notifier);

    // 默认图标颜色
    final defaultIconColor = isDark ? Colors.white70 : Colors.black87;

    switch (state.status) {
      case MouseRecorderStatus.idle:
        return MirrorToolbarButton(
          icon: Icon(
            Icons.gesture,
            size: 18,
            color: defaultIconColor,
          ),
          tooltip: context.l10n.t('startRecordMouse'),
          onPressed: notifier.startRecording,
        );

      case MouseRecorderStatus.recording:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MirrorToolbarButton(
              icon: const Icon(
                CupertinoIcons.stop_fill,
                size: 18,
                color: Colors.redAccent,
              ),
              badge: const _PulsingDotBadge(),
              tooltip: context.l10n.t('stopRecordMouse'),
              onPressed: notifier.stopRecording,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 6),
              child: Text(
                _formatDuration(state.recordDurationMs),
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );

      case MouseRecorderStatus.ready:
        final count = state.actionCount;
        final seconds = (state.recordDurationMs / 1000).toStringAsFixed(1);
        final tooltip = context.l10n
            .t('mouseTrackRecorded')
            .replaceAll('{count}', '$count')
            .replaceAll('{duration}', seconds);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MirrorToolbarButton(
              icon: const Icon(
                Icons.play_arrow_rounded,
                size: 22,
                color: Colors.greenAccent,
              ),
              tooltip: '${context.l10n.t('playMouseTrack')} ($tooltip)',
              onPressed: () => notifier.playTrack(),
            ),
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.clear_circled,
                size: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              tooltip: context.l10n.t('clearMouseTrack'),
              onPressed: notifier.clear,
            ),
          ],
        );

      case MouseRecorderStatus.playing:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MirrorToolbarButton(
              icon: const Icon(
                CupertinoIcons.pause_fill,
                size: 16,
                color: Colors.orangeAccent,
              ),
              tooltip: context.l10n.t('pauseMouseTrack'),
              onPressed: notifier.pausePlaying,
            ),
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.stop_fill,
                size: 16,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
              tooltip: context.l10n.t('stopPlayMouseTrack'),
              onPressed: notifier.stopPlaying,
            ),
            if (state.playProgress > 0)
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 6),
                child: Text(
                  '${(state.playProgress * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        );

      case MouseRecorderStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MirrorToolbarButton(
              icon: const Icon(
                Icons.play_arrow_rounded,
                size: 22,
                color: Colors.orangeAccent,
              ),
              tooltip: context.l10n.t('resumeMouseTrack'),
              onPressed: () => notifier.resumePlaying(),
            ),
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.stop_fill,
                size: 16,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
              tooltip: context.l10n.t('stopPlayMouseTrack'),
              onPressed: notifier.stopPlaying,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 6),
              child: Text(
                '${(state.playProgress * 100).toInt()}% (暂停)',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
    }
  }
}

/// 录制中的动态红色呼吸点
class _PulsingDotBadge extends StatefulWidget {
  const _PulsingDotBadge();

  @override
  State<_PulsingDotBadge> createState() => _PulsingDotBadgeState();
}

class _PulsingDotBadgeState extends State<_PulsingDotBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.25).animate(_controller),
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
