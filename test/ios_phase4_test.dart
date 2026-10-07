import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/dal/rust_dal_bridge.dart';
import 'package:any_deck/core/cron/cron_scheduler_service.dart';

void main() {
  group('Phase 4: iOS Wireless & Automation Unit Tests', () {
    test('RustDalBridge native library availability', () {
      final bridge = RustDalBridge.instance;
      expect(bridge.isAvailable, isTrue);
    });

    test('CronJob JSON serialization and deserialization', () {
      const job = CronJob(
        id: 'job_test_01',
        name: 'Device Health Check',
        expression: '*/5 * * * *',
        lastRun: 1700000000,
        runCount: 12,
      );

      final json = job.toJson();
      expect(json['id'], 'job_test_01');
      expect(json['name'], 'Device Health Check');
      expect(json['expression'], '*/5 * * * *');
      expect(json['last_run'], 1700000000);
      expect(json['run_count'], 12);

      final parsed = CronJob.fromJson(json);
      expect(parsed.id, job.id);
      expect(parsed.name, job.name);
      expect(parsed.expression, job.expression);
      expect(parsed.lastRun, job.lastRun);
      expect(parsed.runCount, job.runCount);
    });

    test('CronSchedulerService registration and execution', () async {
      final service = CronSchedulerService();
      if (!RustDalBridge.instance.isAvailable) return;

      // 1. 添加定时任务
      final added = await service.addJob(
        id: 'ios_phase4_audit',
        name: 'Daily Inspection',
        expression: '0 12 * * *',
      );
      expect(added, isTrue);

      // 2. 查询列表
      final jobs = await service.listJobs();
      expect(jobs.any((j) => j.id == 'ios_phase4_audit'), isTrue);

      // 3. 移除定时任务
      final removed = await service.removeJob('ios_phase4_audit');
      expect(removed, isTrue);

      final afterRemove = await service.listJobs();
      expect(afterRemove.any((j) => j.id == 'ios_phase4_audit'), isFalse);
    });

  });
}
