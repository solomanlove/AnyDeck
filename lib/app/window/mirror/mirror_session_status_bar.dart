import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ios/ios_mirror_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/scrcpy/rust_device_bridge.dart';

/// 展示当前投屏 Session 时长，供标题栏复用。
class MirrorSessionDuration extends StatefulWidget {
  const MirrorSessionDuration({super.key});

  @override
  State<MirrorSessionDuration> createState() => _MirrorSessionDurationState();
}

class _MirrorSessionDurationState extends State<MirrorSessionDuration> {
  Timer? _timer;
  late final DateTime _startedAt;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds = DateTime.now().difference(_startedAt).inSeconds;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatSessionDuration(_elapsedSeconds),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// 展示投屏实际视频帧率，固定放在右侧工具栏底部。
class MirrorSessionFps extends ConsumerStatefulWidget {
  const MirrorSessionFps({
    super.key,
    required this.deviceId,
    required this.isIos,
    required this.isHarmony,
    this.airplayHandle,
  });

  final String deviceId;
  final bool isIos;
  final bool isHarmony;
  final int? airplayHandle;

  @override
  ConsumerState<MirrorSessionFps> createState() => _MirrorSessionFpsState();
}

class _MirrorSessionFpsState extends ConsumerState<MirrorSessionFps> {
  Timer? _timer;
  DateTime? _lastSampleAt;
  int? _lastFrameCount;
  int? _fps;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
    _sample();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sample() {
    if (!mounted) return;
    final now = DateTime.now();
    int? nextFps;
    if (widget.airplayHandle != null) {
      final frames = RustDeviceBridge.instance.decodedFrames(
        widget.airplayHandle!,
      );
      nextFps = _calculateFps(frames, now);
    } else if (widget.isIos) {
      final frames = (ref.read(
        iosUsbFrameProvider(widget.deviceId),
      )['frames'] as num?)?.toInt();
      if (frames != null) nextFps = _calculateFps(frames, now);
    } else {
      final frames = widget.isHarmony
          ? ref
                .read(harmonyMirrorServiceProvider)
                .getDecodedFrames(widget.deviceId)
          : ref
                .read(embeddedScrcpyServiceProvider)
                .getDecodedFrames(widget.deviceId);
      if (frames != null) nextFps = _calculateFps(frames, now);
    }
    setState(() {
      _fps = nextFps;
    });
  }

  int? _calculateFps(int frames, DateTime now) {
    final previousFrames = _lastFrameCount;
    final previousTime = _lastSampleAt;
    _lastFrameCount = frames;
    _lastSampleAt = now;
    if (previousFrames == null || previousTime == null) return null;
    final seconds = now.difference(previousTime).inMilliseconds / 1000;
    if (seconds <= 0) return null;
    return ((frames - previousFrames) / seconds).round().clamp(0, 240);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'FPS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
          Text(
            '${_fps ?? '--'}',
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface,
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatSessionDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainingSeconds = seconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainingSeconds.toString().padLeft(2, '0')}';
}
