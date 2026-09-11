import 'package:any_deck/core/device_info/device_memory_info.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证内存口径、旧内核回退及历史缓存的兼容边界。
void main() {
  test('优先使用 MemAvailable，不把全部缓存算作已用', () {
    final memory = DeviceMemoryInfo.parse('''
MemTotal: 8388608 kB
MemAvailable: 2097152 kB
MemFree: 1048576 kB
Buffers: 0 kB
Cached: 0 kB
''');
    expect(memory.total, '8.00G');
    expect(memory.used, '6.00G');
  });

  test('旧内核扣除空闲与可回收缓存，并排除共享内存', () {
    final memory = DeviceMemoryInfo.parse('''
MemTotal: 8388608 kB
MemFree: 1048576 kB
Buffers: 524288 kB
Cached: 1048576 kB
SReclaimable: 524288 kB
Shmem: 1048576 kB
''');
    expect(memory.used, '6.00G');
  });

  test('字段不足时保留总量并隐藏未知占用', () {
    final memory = DeviceMemoryInfo.parse('MemTotal: 8388608 kB');
    expect(memory.total, '8.00G');
    expect(memory.used, '-');
    expect(DeviceMemoryInfo.parse('Permission denied').total, '-');
    expect(DeviceMemoryInfo.parse('MemTotal: 0 kB').total, '-');
  });

  test('可用内存边界不会产生负数或超过总量的已用值', () {
    expect(
      DeviceMemoryInfo.parse('MemTotal: 1024 kB\nMemAvailable: 2048 kB').usedKb,
      0,
    );
    expect(
      DeviceMemoryInfo.parse('MemTotal: 1024 kB\nMemAvailable: 0 kB').usedKb,
      1024,
    );
  });

  test('旧缓存缺少占用字段时不误显示为零', () {
    final overview = DeviceOverview.fromJson({'memory': '8.00G'});
    expect(overview.memory, '8.00G');
    expect(overview.memoryUsed, '-');
  });
}
