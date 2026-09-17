import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../../core/harmony/harmony_mirror_service.dart';
import '../models/mouse_track_recorder_state.dart';
import '../models/recorded_mouse_action.dart';
import 'mouse_track_serializer.dart';

export '../models/mouse_track_recorder_state.dart';

/// 鼠标路径录制与回放控制器
class MouseTrackRecorderNotifier extends Notifier<MouseTrackRecorderState> {
  MouseTrackRecorderNotifier(this.deviceId);

  final String deviceId;

  /// 录制时钟
  final Stopwatch _recordStopwatch = Stopwatch();

  /// 临时收集的动作列表
  final List<RecordedMouseAction> _recordedActions = [];

  /// 定时刷新录制时长的 Timer
  Timer? _tickerTimer;

  /// 是否中断当前回放的标志位
  bool _abortPlayback = false;

  /// 录制起始时的基准屏幕宽高
  int _baseWidth = 0;
  int _baseHeight = 0;

  @override
  MouseTrackRecorderState build() {
    ref.onDispose(() {
      _tickerTimer?.cancel();
      _abortPlayback = true;
      _recordStopwatch.stop();
    });

    return const MouseTrackRecorderState(
      status: MouseRecorderStatus.idle,
      recordDurationMs: 0,
      actionCount: 0,
    );
  }

  /// 判断当前设备是否为鸿蒙设备
  bool get _isHarmony =>
      deviceId.startsWith('harmony:') ||
      ref.read(activeHarmonyMirrorProvider(deviceId)) != null ||
      ref.read(harmonyMirrorServiceProvider).isActive(deviceId) ||
      ref.read(deviceRegistryProvider).any(
            (d) => d.id == deviceId && d.isHarmony,
          );

  /// 发送二进制控制消息到底层投屏服务
  void _sendControlMessage(Uint8List message) {
    if (_isHarmony) {
      ref.read(harmonyMirrorServiceProvider).sendControl(
            deviceId: deviceId,
            controlMessage: message,
          );
    } else {
      ref.read(embeddedScrcpyServiceProvider).sendControl(
            deviceId: deviceId,
            controlMessage: message,
          );
    }
  }

  /// 开始录制鼠标操作路径
  void startRecording() {
    if (state.isRecording || state.isPlaying) return;

    _recordedActions.clear();
    _recordStopwatch.reset();
    _recordStopwatch.start();

    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (state.isRecording) {
        state = state.copyWith(
          recordDurationMs: _recordStopwatch.elapsedMilliseconds,
          actionCount: _recordedActions.length,
        );
      }
    });

    state = state.copyWith(
      status: MouseRecorderStatus.recording,
      recordDurationMs: 0,
      actionCount: 0,
      clearTrack: true,
      clearError: true,
    );
    debugPrint('[MouseRecorder] Started recording for device: $deviceId');
  }

  /// 记录一个触控事件 (DOWN / MOVE / UP / CANCEL)
  void recordTouch({
    required int action,
    required int x,
    required int y,
    required int screenWidth,
    required int screenHeight,
    double pressure = 1.0,
  }) {
    if (!state.isRecording) return;

    if (_baseWidth == 0 && screenWidth > 0) {
      _baseWidth = screenWidth;
      _baseHeight = screenHeight;
    }

    final RecordedActionType type;
    switch (action) {
      case 0:
        type = RecordedActionType.down;
        break;
      case 1:
        type = RecordedActionType.up;
        break;
      case 2:
        type = RecordedActionType.move;
        break;
      default:
        type = RecordedActionType.cancel;
        break;
    }

    // 过滤超高频无位移抖动点
    if (type == RecordedActionType.move && _recordedActions.isNotEmpty) {
      final last = _recordedActions.last;
      if (last.type == RecordedActionType.move &&
          last.x == x &&
          last.y == y) {
        return;
      }
    }

    final actionFrame = RecordedMouseAction(
      deltaMs: _recordStopwatch.elapsedMilliseconds,
      type: type,
      x: x,
      y: y,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      pressure: pressure,
    );

    _recordedActions.add(actionFrame);

    // 适度更新 state，驱动实时轨迹延伸
    if (type != RecordedActionType.move || _recordedActions.length % 3 == 0) {
      state = state.copyWith(
        currentAction: actionFrame,
        recordingActions: List.unmodifiable(_recordedActions),
      );
    }
  }

  /// 记录一个滚轮滚动事件
  void recordScroll({
    required int x,
    required int y,
    required int screenWidth,
    required int screenHeight,
    required double hScroll,
    required double vScroll,
  }) {
    if (!state.isRecording) return;

    final actionFrame = RecordedMouseAction(
      deltaMs: _recordStopwatch.elapsedMilliseconds,
      type: RecordedActionType.scroll,
      x: x,
      y: y,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      hScroll: hScroll,
      vScroll: vScroll,
    );

    _recordedActions.add(actionFrame);
  }

  /// 停止录制
  void stopRecording() {
    if (!state.isRecording) return;

    _tickerTimer?.cancel();
    _tickerTimer = null;
    final totalDuration = _recordStopwatch.elapsedMilliseconds;
    _recordStopwatch.stop();

    if (_recordedActions.isEmpty) {
      state = const MouseTrackRecorderState(
        status: MouseRecorderStatus.idle,
        recordDurationMs: 0,
        actionCount: 0,
      );
      debugPrint('[MouseRecorder] Stopped with 0 actions, reset to idle.');
      return;
    }

    final track = RecordedMouseTrack(
      deviceId: deviceId,
      createdAt: DateTime.now(),
      totalDurationMs: totalDuration,
      baseWidth: _baseWidth > 0 ? _baseWidth : 1080,
      baseHeight: _baseHeight > 0 ? _baseHeight : 1920,
      actions: List.unmodifiable(_recordedActions),
    );

    state = state.copyWith(
      status: MouseRecorderStatus.ready,
      currentTrack: track,
      recordDurationMs: totalDuration,
      actionCount: track.actionCount,
      recordingActions: const [],
      playProgress: 0.0,
      clearAction: true,
      clearError: true,
    );
    debugPrint(
      '[MouseRecorder] Stopped recording: ${track.actionCount} actions in ${totalDuration}ms',
    );
  }

  /// 是否暂停当前回放的标志位
  bool _isPaused = false;

  /// 回放执行录制的操作路径（支持指定起始帧断点续播）
  Future<void> playTrack({
    int startIndex = 0,
    int? currentWidth,
    int? currentHeight,
    double speed = 1.0,
  }) async {
    final track = state.currentTrack;
    if (track == null || track.actions.isEmpty) return;
    if (state.isPlaying) return;

    if (startIndex >= track.actions.length) {
      startIndex = 0;
    }

    _abortPlayback = false;
    _isPaused = false;

    state = state.copyWith(
      status: MouseRecorderStatus.playing,
      playProgress: startIndex == 0 ? 0.0 : state.playProgress,
      playActionIndex: startIndex,
      clearError: true,
    );

    final actualSpeed = speed <= 0 ? 1.0 : speed;
    final startDeltaMs = startIndex > 0 ? track.actions[startIndex].deltaMs : 0;
    final playbackStopwatch = Stopwatch()..start();
    final totalDuration = track.totalDurationMs;

    debugPrint(
      '[MouseRecorder] Start playback (start=$startIndex/${track.actionCount}, speed=${actualSpeed}x)',
    );

    try {
      for (int i = startIndex; i < track.actions.length; i++) {
        if (_abortPlayback || _isPaused) {
          debugPrint(
            '[MouseRecorder] Playback interrupted (abort=$_abortPlayback, pause=$_isPaused)',
          );
          break;
        }

        final action = track.actions[i];
        final targetMs = ((action.deltaMs - startDeltaMs) / actualSpeed).round();
        final currentElapsed = playbackStopwatch.elapsedMilliseconds;

        if (targetMs > currentElapsed) {
          final waitDuration = Duration(milliseconds: targetMs - currentElapsed);
          await Future<void>.delayed(waitDuration);
        }

        if (_abortPlayback || _isPaused) break;

        final message = MouseTrackSerializer.serializeAction(
          action,
          currentWidth: currentWidth,
          currentHeight: currentHeight,
        );

        if (message != null) {
          _sendControlMessage(message);
        }

        // 更新当前触点位置与进度条，驱动涟漪动画
        final progress = totalDuration > 0
            ? (action.deltaMs / totalDuration).clamp(0.0, 1.0)
            : 0.0;
        state = state.copyWith(
          currentAction: action,
          playActionIndex: i,
          playProgress: progress,
        );
      }
    } catch (e, stack) {
      debugPrint('[MouseRecorder] Playback error: $e\n$stack');
      state = state.copyWith(errorMessage: e.toString());
    } finally {
      playbackStopwatch.stop();

      // 如果属于主动暂停，则向设备补发 UP 防止物理触点悬挂，并保留 paused 状态
      if (_isPaused) {
        final releaseMsg = MouseTrackSerializer.serializeTouchEvent(
          action: 1, // UP
          x: 0,
          y: 0,
          screenWidth: currentWidth ?? track.baseWidth,
          screenHeight: currentHeight ?? track.baseHeight,
          pressure: 0,
        );
        _sendControlMessage(releaseMsg);
        state = state.copyWith(status: MouseRecorderStatus.paused);
        debugPrint('[MouseRecorder] Playback paused at index ${state.playActionIndex}');
      } else {
        // 安全释放：无论是否正常结束，均补发一次 UP 事件防止触点粘在屏幕上
        final releaseMsg = MouseTrackSerializer.serializeTouchEvent(
          action: 1, // UP
          x: 0,
          y: 0,
          screenWidth: currentWidth ?? track.baseWidth,
          screenHeight: currentHeight ?? track.baseHeight,
          pressure: 0,
        );
        _sendControlMessage(releaseMsg);

        state = state.copyWith(
          status: MouseRecorderStatus.ready,
          playProgress: 1.0,
          playActionIndex: 0,
          clearAction: true,
        );
        debugPrint('[MouseRecorder] Playback finished.');
      }
    }
  }

  /// 暂停当前回放
  void pausePlaying() {
    if (!state.isPlaying) return;
    _isPaused = true;
  }

  /// 继续执行已暂停的回放
  Future<void> resumePlaying({
    int? currentWidth,
    int? currentHeight,
    double speed = 1.0,
  }) async {
    if (state.status != MouseRecorderStatus.paused) return;
    final nextIndex = state.playActionIndex + 1;
    await playTrack(
      startIndex: nextIndex,
      currentWidth: currentWidth,
      currentHeight: currentHeight,
      speed: speed,
    );
  }

  /// 彻底中止回放并重置为就绪状态
  void stopPlaying() {
    if (!state.isPlaying && !state.isPaused) return;
    _abortPlayback = true;
    _isPaused = false;
    state = state.copyWith(
      status: MouseRecorderStatus.ready,
      playProgress: 0.0,
      playActionIndex: 0,
      clearAction: true,
    );
    debugPrint('[MouseRecorder] Stop playing requested and reset.');
  }

  /// 清空当前已录制的路径
  void clear() {
    _abortPlayback = true;
    _tickerTimer?.cancel();
    _tickerTimer = null;
    _recordStopwatch.stop();
    _recordedActions.clear();

    state = const MouseTrackRecorderState(
      status: MouseRecorderStatus.idle,
      recordDurationMs: 0,
      actionCount: 0,
    );
    debugPrint('[MouseRecorder] Cleared recorded track for device: $deviceId');
  }
}

/// 鼠标路径录制器 Riverpod Provider
final mouseTrackRecorderProvider = NotifierProvider.family<
    MouseTrackRecorderNotifier, MouseTrackRecorderState, String>(
  MouseTrackRecorderNotifier.new,
);
