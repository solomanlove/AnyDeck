part of '../dashboard_screen.dart';

/// 批量应用操作进度模型。
class _BatchProgressState {
  const _BatchProgressState({
    required this.title,
    required this.current,
    required this.total,
    required this.currentName,
  });

  final String title;
  final int current;
  final int total;
  final String currentName;

  double get progress => total == 0 ? 0.0 : current / total;
}
