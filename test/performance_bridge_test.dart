import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/performance/rust_performance_bridge.dart';
import 'package:any_deck/features/performance/performance_data.dart';

void main() {
  test('RustPerformanceBridge instance is accessible and allocates snapshot buffer', () {
    final bridge = RustPerformanceBridge.instance;
    expect(bridge, isNotNull);

    // 对于不存在的模拟设备，Direct Socket 会返回 null 或优雅失败，绝不抛出未捕获异常
    final result = bridge.poll('non_existent_mock_serial_12345');
    expect(result, isNull);

    // 清理缓存不抛异常
    expect(() => bridge.clearCache('non_existent_mock_serial_12345'), returnsNormally);
  });

  test('PerformanceSnapshot model instantiates and exposes fields correctly', () {
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
  });

  test('RustPerformanceBridge polls real attached device via Direct Socket', () {
    final bridge = RustPerformanceBridge.instance;
    final snapshot = bridge.poll('5002ba00');
    expect(snapshot, isNotNull);
    if (snapshot != null) {
      expect(snapshot.totalMemoryMB, greaterThan(0));
      expect(snapshot.cores, isNotEmpty);
      expect(snapshot.batteryLevel, inInclusiveRange(0, 100));
    }
  });
}
