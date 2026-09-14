import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dal/rust_dal_bridge.dart';

/// 定时任务实体
class CronJob {
  const CronJob({
    required this.id,
    required this.name,
    required this.expression,
    this.lastRun = 0,
    this.runCount = 0,
  });

  final String id;
  final String name;
  final String expression;
  final int lastRun;
  final int runCount;

  factory CronJob.fromJson(Map<String, dynamic> json) {
    return CronJob(
      id: json['id'] as String? ?? json['name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      expression: json['expression'] as String? ?? '',
      lastRun: json['last_run'] as int? ?? 0,
      runCount: json['run_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'expression': expression,
        'last_run': lastRun,
        'run_count': runCount,
      };
}

/// 基于 Rust 原生定时引擎的轻量 Cron 调度服务。
/// 支持 5 字段标准 Cron 表达式（分钟 小时 日 月 星期），
/// 用于自动化性能巡检、定时截图、脚本批处理及 AirPlay 伴生任务。
class CronSchedulerService {
  CronSchedulerService({RustDalBridge? bridge})
      : _bridge = bridge ?? RustDalBridge.instance;

  final RustDalBridge _bridge;

  /// 添加或更新一个定时调度任务
  Future<bool> addJob({
    required String id,
    required String name,
    required String expression,
  }) async {
    if (!_bridge.isAvailable) {
      debugPrint('[CronSchedulerService] RustDalBridge 不可用');
      return false;
    }
    return _bridge.cronAddJob(id: id, name: name, expression: expression);
  }

  /// 移除指定 ID 的定时任务
  Future<bool> removeJob(String id) async {
    if (!_bridge.isAvailable) return false;
    return _bridge.cronRemoveJob(id);
  }

  /// 获取当前已注册的所有定时任务列表
  Future<List<CronJob>> listJobs() async {
    if (!_bridge.isAvailable) return [];
    try {
      final list = _bridge.cronListJobs();
      return list.map(CronJob.fromJson).toList();
    } catch (e) {
      debugPrint('[CronSchedulerService] 解析定时任务列表失败: $e');
    }
    return [];
  }
}

/// 全局定时调度服务 Provider
final cronSchedulerServiceProvider = Provider<CronSchedulerService>((ref) {
  return CronSchedulerService();
});
