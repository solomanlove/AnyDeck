import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:any_deck/core/dal/rust_dal_bridge.dart';
import 'package:any_deck/core/ios/ios_ble_mouse_service.dart';
import 'package:any_deck/core/ios/ios_wda_client.dart';
import 'package:any_deck/core/cron/cron_scheduler_service.dart';

void main() {
  group('Phase 4: iOS Wireless & Automation Unit Tests', () {
    test('RustDalBridge native library availability', () {
      final bridge = RustDalBridge.instance;
      expect(bridge.isAvailable, isTrue);
    });

    test('BLE Mouse HID Report and State Controller', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(iosBleMouseProvider.notifier);
      final initial = container.read(iosBleMouseProvider);
      expect(initial.isEnabled, isFalse);
      expect(initial.state, BleMouseState.stopped);
      expect(initial.sensitivity, 1.0);

      notifier.setSensitivity(2.0);
      expect(container.read(iosBleMouseProvider).sensitivity, 2.0);

      // 启动模拟器
      final started = await notifier.start();
      if (RustDalBridge.instance.isAvailable) {
        expect(started, isTrue);
        expect(container.read(iosBleMouseProvider).isEnabled, isTrue);

        // 验证底层的 FFI 状态查询与报告发送
        final status = RustDalBridge.instance.bleMouseStatus();
        expect(status, greaterThanOrEqualTo(0));

        final sent = RustDalBridge.instance.bleMouseSend(
          buttons: 0,
          dx: 10,
          dy: -15,
          wheel: 0,
        );
        expect(sent, isTrue);

        // 停止模拟器
        final stopped = await notifier.stop();
        expect(stopped, isTrue);
        expect(container.read(iosBleMouseProvider).isEnabled, isFalse);
      }
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

    test('IosWdaClient request structure and fallbacks', () async {
      final client = IosWdaClient(port: 8100);
      expect(client.port, 8100);

      // 验证在没有真机连接时，WDA 请求会优雅处理连接超时或失败，而不发生崩溃
      final res = await client.getStatus();
      expect(res.containsKey('success'), isTrue);
    });
  });
}
