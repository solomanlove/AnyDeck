import 'dart:async';

import 'package:any_deck/core/logcat/logcat_controller.dart';
import 'package:any_deck/core/logcat/logcat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/controlled_process.dart';

/// 验证 PID 辅助查询与主采集共享生命周期，慢查询不阻塞采集。
void main() {
  test('慢 PID 查询不阻止采集启动、不重入，停止后全部回收', () async {
    SharedPreferences.setMockInitialValues({});
    final query = ControlledProcess();
    final capture = ControlledProcess();
    var queries = 0, captures = 0;
    final provider = NotifierProvider<LogcatController, LogcatState>(
      () => LogcatController(
        startProcess: (_, args) async {
          if (args.contains('ps')) {
            queries++;
            return query;
          }
          captures++;
          return capture;
        },
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(provider.notifier);
    await controller.start('phone');
    expect(captures, 1);
    expect(queries, 1);
    expect(container.read(provider).isRunning, isTrue);
    await controller.stop();
    await Future<void>.delayed(Duration.zero);
    expect(query.signals, isNotEmpty);
    expect(capture.signals, isNotEmpty);
    expect(container.read(provider).isRunning, isFalse);
  });
  test('慢 PID 查询跨周期不重入，主采集退出也取消辅助任务', () {
    fakeAsync((clock) {
      SharedPreferences.setMockInitialValues({});
      final query = ControlledProcess();
      final capture = ControlledProcess();
      var queries = 0;
      final provider = NotifierProvider<LogcatController, LogcatState>(
        () => LogcatController(
          startProcess: (_, args) async {
            if (args.contains('ps')) {
              queries++;
              return query;
            }
            return capture;
          },
        ),
      );
      final container = ProviderContainer();
      final controller = container.read(provider.notifier);
      unawaited(controller.start('phone'));
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 7));
      expect(queries, 1);
      capture.finish();
      clock.flushMicrotasks();
      expect(query.signals, isNotEmpty);
      clock.elapse(const Duration(seconds: 10));
      expect(queries, 1);
      container.dispose();
      clock.flushMicrotasks();
    });
  });
}
