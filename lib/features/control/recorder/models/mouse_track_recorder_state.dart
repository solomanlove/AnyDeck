import '../models/recorded_mouse_action.dart';

/// 鼠标路径录制器的生命周期状态
enum MouseRecorderStatus {
  /// 空闲状态（无录制数据）
  idle,

  /// 正在录制鼠标手势与路径
  recording,

  /// 已录制完成，等待回放执行
  ready,

  /// 正在回放执行录制的操作
  playing,

  /// 回放已暂停，支持随时恢复继续
  paused,
}

/// 鼠标操作路径录制器状态模型
class MouseTrackRecorderState {
  const MouseTrackRecorderState({
    required this.status,
    required this.recordDurationMs,
    required this.actionCount,
    this.currentTrack,
    this.currentAction,
    this.recordingActions = const [],
    this.playProgress = 0.0,
    this.playActionIndex = 0,
    this.errorMessage,
  });

  /// 当前状态
  final MouseRecorderStatus status;

  /// 正在录制时的持续毫秒数
  final int recordDurationMs;

  /// 已捕获的动作帧数
  final int actionCount;

  /// 已录制完毕的轨迹对象
  final RecordedMouseTrack? currentTrack;

  /// 当前正在发生或回放的实时动作帧
  final RecordedMouseAction? currentAction;

  /// 正在录制中的动作列表（供实时绘制未完成轨迹）
  final List<RecordedMouseAction> recordingActions;

  /// 回放进度 (0.0 ~ 1.0)
  final double playProgress;

  /// 回放时当前已执行到的帧索引
  final int playActionIndex;

  /// 异常信息
  final String? errorMessage;

  /// 是否正在录制中
  bool get isRecording => status == MouseRecorderStatus.recording;

  /// 是否正在回放执行中
  bool get isPlaying => status == MouseRecorderStatus.playing;

  /// 是否处于暂停状态
  bool get isPaused => status == MouseRecorderStatus.paused;

  /// 是否有可回放的有效轨迹
  bool get hasTrack =>
      currentTrack != null && currentTrack!.actions.isNotEmpty;

  /// 当前可用于绘制的动作列表
  List<RecordedMouseAction> get activeActions =>
      isRecording ? recordingActions : (currentTrack?.actions ?? const []);

  MouseTrackRecorderState copyWith({
    MouseRecorderStatus? status,
    int? recordDurationMs,
    int? actionCount,
    RecordedMouseTrack? currentTrack,
    RecordedMouseAction? currentAction,
    List<RecordedMouseAction>? recordingActions,
    double? playProgress,
    int? playActionIndex,
    String? errorMessage,
    bool clearTrack = false,
    bool clearAction = false,
    bool clearError = false,
  }) {
    return MouseTrackRecorderState(
      status: status ?? this.status,
      recordDurationMs: recordDurationMs ?? this.recordDurationMs,
      actionCount: actionCount ?? this.actionCount,
      currentTrack: clearTrack ? null : (currentTrack ?? this.currentTrack),
      currentAction: clearAction ? null : (currentAction ?? this.currentAction),
      recordingActions: recordingActions ?? this.recordingActions,
      playProgress: playProgress ?? this.playProgress,
      playActionIndex: playActionIndex ?? this.playActionIndex,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
