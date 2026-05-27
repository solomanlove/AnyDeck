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
