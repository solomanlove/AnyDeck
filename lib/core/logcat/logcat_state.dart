import 'logcat_entry.dart';

/// logcat 实时面板使用的不可变 UI 状态。
class LogcatState {
  const LogcatState({
    this.entries = const [],
    this.isRunning = false,
    this.viewMode = LogcatViewMode.standard,
    this.levelFilter = LogcatLevelFilter.verbose,
    this.packageFilter = '',
    this.tagFilter = '',
    this.textFilter = '',
    this.packageFilterHistory = const [],
    this.tagFilterHistory = const [],
    this.textFilterHistory = const [],
    this.isPaused = false,
    this.autoScroll = true,
    this.wrapLines = false,
    this.error,
  });

  final List<LogcatEntry> entries;
  final bool isRunning;
  final LogcatViewMode viewMode;
  final LogcatLevelFilter levelFilter;
  final String packageFilter;
  final String tagFilter;
  final String textFilter;
  final List<String> packageFilterHistory;
  final List<String> tagFilterHistory;
  final List<String> textFilterHistory;
  final bool isPaused;
  final bool autoScroll;
  final bool wrapLines;
  final String? error;

  /// 创建新的状态对象，未传入字段沿用当前值。
  LogcatState copyWith({
    List<LogcatEntry>? entries,
    bool? isRunning,
    LogcatViewMode? viewMode,
    LogcatLevelFilter? levelFilter,
    String? packageFilter,
    String? tagFilter,
    String? textFilter,
    List<String>? packageFilterHistory,
    List<String>? tagFilterHistory,
    List<String>? textFilterHistory,
    bool? isPaused,
    bool? autoScroll,
    bool? wrapLines,
    String? error,
  }) {
    return LogcatState(
      entries: entries ?? this.entries,
      isRunning: isRunning ?? this.isRunning,
      viewMode: viewMode ?? this.viewMode,
      levelFilter: levelFilter ?? this.levelFilter,
      packageFilter: packageFilter ?? this.packageFilter,
      tagFilter: tagFilter ?? this.tagFilter,
      textFilter: textFilter ?? this.textFilter,
      packageFilterHistory: packageFilterHistory ?? this.packageFilterHistory,
      tagFilterHistory: tagFilterHistory ?? this.tagFilterHistory,
      textFilterHistory: textFilterHistory ?? this.textFilterHistory,
      isPaused: isPaused ?? this.isPaused,
      autoScroll: autoScroll ?? this.autoScroll,
      wrapLines: wrapLines ?? this.wrapLines,
      error: error,
    );
  }
}
