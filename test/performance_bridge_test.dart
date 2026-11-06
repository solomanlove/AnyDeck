import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/performance/rust_performance_bridge.dart';
import 'package:any_deck/core/performance/performance_sampler.dart';
import 'package:any_deck/features/performance/performance_data.dart';

/// 真实加载测试 C-ABI 底座，验证 worker 隔离及原生缓冲区释放，不连接真机。
void main() {
  late Directory directory;
  late String libraryPath;
  late int Function() allocations, polls;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'anydeck_performance_test_',
    );
    libraryPath =
        '${directory.path}/fixture.${Platform.isMacOS ? 'dylib' : 'so'}';
    final result = await Process.run('cc', [
      if (Platform.isMacOS) '-dynamiclib' else '-shared',
      '-fPIC',
      '-std=c11',
      'test/fixtures/performance_bridge_stub.c',
      '-o',
      libraryPath,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final library = DynamicLibrary.open(libraryPath);
    allocations = library.lookupFunction<Int32 Function(), int Function()>(
      'test_allocations',
    );
    polls = library.lookupFunction<Int32 Function(), int Function()>(
      'test_polls',
    );
  });
  tearDownAll(() async {
    await directory.delete(recursive: true);
  });

  test('FFI 快照布局、空结果与释放在测试底座上验证', () {
    final bridge = RustPerformanceBridge.open(libraryPath: libraryPath);
    expect(bridge.poll('missing'), isNull);
    final snapshot = bridge.poll('fixture')!;
    expect(snapshot.totalMemoryMB, 8000);
    expect(snapshot.cores.single.frequencyMHz, 1800);
    expect(snapshot.foregroundAppPackage, 'com.example.app');
    bridge.clearCache('fixture');
    bridge.dispose();
    expect(allocations(), 0);
  });

  test('慢 FFI 不阻塞主 Isolate，相同请求只执行一次', () async {
    final sampler = PerformanceSampler(libraryPath: libraryPath);
    addTearDown(sampler.dispose);
    final before = polls();
    final first = sampler.poll('slow');
    expect(identical(first, sampler.poll('slow')), isTrue);
    var completed = false;
    unawaited(first.then((_) => completed = true));
    await _until(() => polls() > before);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(completed, isFalse);
    expect(await sampler.poll('other'), isNull);
    expect((await first)!.batteryLevel, 90);
    expect(polls() - before, 1);
    sampler.dispose();
    await _until(() => allocations() == 0);
  });

  test('关闭信号等待慢原生调用完成并释放资源，切页恢复可等待此信号', () async {
    final sampler = PerformanceSampler(libraryPath: libraryPath);
    final before = polls();
    final pending = sampler.poll('slow');
    await _until(() => polls() > before);
    sampler.dispose();
    expect(await pending, isNull);
    var stopped = false;
    unawaited(sampler.stopped.then((_) => stopped = true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(stopped, isFalse);
    await sampler.stopped.timeout(const Duration(seconds: 3));
    expect(allocations(), 0);
  });

  test('连续 await 的新请求不会复用上一轮已完成的 Future', () async {
    final sampler = PerformanceSampler(libraryPath: libraryPath);
    addTearDown(sampler.dispose);
    final before = polls();
    await sampler.poll('fixture');
    await sampler.poll('fixture');
    expect(polls() - before, 2);
    sampler.dispose();
    await _until(() => allocations() == 0);
  });

  test('超时返回空结果，worker 随后释放原生资源', () async {
    final sampler = PerformanceSampler(
      libraryPath: libraryPath,
      timeout: const Duration(milliseconds: 70),
    );
    expect(await sampler.poll('slow'), isNull);
    await _until(() => allocations() == 0);
  });

  test('启动期间销毁丢弃结果且不遗留原生缓冲区', () async {
    final sampler = PerformanceSampler(libraryPath: libraryPath);
    final pending = sampler.poll('slow');
    sampler.dispose();
    expect(await pending, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _until(() => allocations() == 0);
  });

  test('动态库不可用时正常回退，不挂起调用方', () async {
    final sampler = PerformanceSampler(
      libraryPath: '${directory.path}/missing',
    );
    expect(await sampler.poll('fixture'), isNull);
    sampler.dispose();
  });

  test(
    'PerformanceSnapshot model instantiates and exposes fields correctly',
    () {
      final now = DateTime.now();
      final snapshot = PerformanceSnapshot(
        uptime: '1天02时03分04秒',
        batteryLevel: 90,
        isCharging: true,
        totalMemoryMB: 8000.0,
        usedMemoryMB: 3000.0,
        memoryUsagePercent: 37.5,
        foregroundAppPackage: 'com.example.app',
        overallCpuUsage: 15.5,
        cores: const [
          CpuCoreSnapshot(id: 0, usage: 12.0, frequencyMHz: 1800.0),
          CpuCoreSnapshot(id: 1, usage: 18.0, frequencyMHz: 1800.0),
        ],
        totalFrames: 1000,
        fps: 60.0,
        timestamp: now,
      );

      expect(snapshot.uptime, '1天02时03分04秒');
      expect(snapshot.batteryLevel, 90);
      expect(snapshot.isCharging, isTrue);
      expect(snapshot.memoryUsagePercent, 37.5);
      expect(snapshot.foregroundAppPackage, 'com.example.app');
      expect(snapshot.overallCpuUsage, 15.5);
      expect(snapshot.cores.length, 2);
      expect(snapshot.fps, 60.0);
    },
  );
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('worker 未在期限内完成/释放');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
