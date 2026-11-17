part of '../dashboard_screen.dart';

/// 单次计划任务及其目标设备，供批量计划弹窗与执行器共享。
class ScheduledDeviceTask {
  final String id;
  final String title;
  final String actionType; // 'screenshot', 'install', 'push', 'script'
  final List<String> targetDeviceIds;
  final DateTime scheduledTime;
  final dynamic payload;
  String status; // 'pending', 'running', 'completed', 'failed', 'cancelled'
  String result;

  ScheduledDeviceTask({
    required this.id,
    required this.title,
    required this.actionType,
    required this.targetDeviceIds,
    required this.scheduledTime,
    required this.payload,
    this.status = 'pending',
    this.result = '',
  });
}

/// 管理计划任务与定时执行生命周期，保留原有批量命令流程。
class ScheduledDeviceTasksNotifier extends Notifier<List<ScheduledDeviceTask>> {
  final Map<String, Timer> _timers = {};

  @override
  List<ScheduledDeviceTask> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
    });
    return [];
  }

  void scheduleTask(ScheduledDeviceTask task, Future<String> Function() execute) {
    state = [...state, task];
    final delay = task.scheduledTime.difference(DateTime.now());
    if (delay.isNegative) {
      _executeTask(task.id, execute);
      return;
    }
    final timer = Timer(delay, () {
      _executeTask(task.id, execute);
    });
    _timers[task.id] = timer;
  }

  void cancelTask(String id) {
    _timers[id]?.cancel();
    _timers.remove(id);
    state = state
        .map((t) => t.id == id ? t.copyWithStatus('cancelled', '已取消') : t)
        .toList();
  }

  Future<void> _executeTask(
    String id,
    Future<String> Function() execute,
  ) async {
    _timers.remove(id);
    state = state
        .map((t) => t.id == id ? t.copyWithStatus('running', '正在执行...') : t)
        .toList();

    try {
      final summary = await execute();
      state = state
          .map((t) => t.id == id ? t.copyWithStatus('completed', summary) : t)
          .toList();
    } catch (e) {
      state = state
          .map((t) => t.id == id ? t.copyWithStatus('failed', '执行出错: $e') : t)
          .toList();
    }
  }
}

extension ScheduledDeviceTaskExtension on ScheduledDeviceTask {
  ScheduledDeviceTask copyWithStatus(String newStatus, String newResult) {
    return ScheduledDeviceTask(
      id: id,
      title: title,
      actionType: actionType,
      targetDeviceIds: targetDeviceIds,
      scheduledTime: scheduledTime,
      payload: payload,
      status: newStatus,
      result: newResult,
    );
  }
}

final scheduledDeviceTasksProvider =
    NotifierProvider<ScheduledDeviceTasksNotifier, List<ScheduledDeviceTask>>(
      ScheduledDeviceTasksNotifier.new,
    );
