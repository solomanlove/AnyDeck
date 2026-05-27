/// logcat 实时面板使用的不可变 UI 状态。
class LogcatState {
  const LogcatState({
    this.lines = const [],
    this.isRunning = false,
    this.filter = '',
    this.error,
  });

  final List<String> lines;
  final bool isRunning;
  final String filter;
  final String? error;

  /// 创建新的状态对象，未传入字段沿用当前值。
  LogcatState copyWith({
    List<String>? lines,
    bool? isRunning,
    String? filter,
    String? error,
  }) {
    return LogcatState(
      lines: lines ?? this.lines,
      isRunning: isRunning ?? this.isRunning,
      filter: filter ?? this.filter,
      error: error,
    );
  }
}
