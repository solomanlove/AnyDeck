import 'package:any_deck/features/performance/performance_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('鸿蒙性能快照使用 BatteryService 百分比与充电状态', () {
    const output = ''' 00:05:24 up  5:24,  0 users,  load average: 9.90
---
BatteryService
capacity: 86
batteryLevel: 1
chargingStatus: 1
---
MemTotal:       8192000 kB
MemAvailable:   4096000 kB
---

---
cpu  100 0 100 800 0 0 0
cpu0 50 0 50 400 0 0 0
---
1800000
---
''';

    final snapshot = PerformanceSnapshot.parse(
      stdout: output,
      prevCpuStats: const {},
      outCpuStats: {},
      prevTotalFrames: 0,
      prevFpsTime: null,
      lastFps: 0,
      outFpsInfo: {},
      isHarmony: true,
    );

    expect(snapshot.batteryLevel, 86);
    expect(snapshot.uptime, '05时24分00秒');
    expect(snapshot.isCharging, isTrue);
    expect(snapshot.totalMemoryMB, 8000);
    expect(snapshot.usedMemoryMB, 4000);
    expect(snapshot.cores.single.frequencyMHz, 1800);
  });

  test('鸿蒙无电量权限时不伪造 100%', () {
    final snapshot = PerformanceSnapshot.parse(
      stdout: '12345 0\n---\npermission denied\n---\n',
      prevCpuStats: const {},
      outCpuStats: {},
      prevTotalFrames: 0,
      prevFpsTime: null,
      lastFps: 0,
      outFpsInfo: {},
      isHarmony: true,
    );

    expect(snapshot.batteryLevel, -1);
    expect(snapshot.isCharging, isFalse);
  });
}
