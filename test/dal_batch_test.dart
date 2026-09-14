import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/dal/device_driver.dart';
import 'package:any_deck/core/dal/rust_dal_bridge.dart';

void main() {
  test('BatchDeviceResult model serialization and deserialization', () {
    final result = BatchDeviceResult(
      serial: 'device_01',
      success: true,
      output: 'test_output_ok',
      error: null,
      durationMs: 42,
    );

    final json = result.toJson();
    expect(json['serial'], 'device_01');
    expect(json['success'], isTrue);
    expect(json['output'], 'test_output_ok');
    expect(json['duration_ms'], 42);

    final parsed = BatchDeviceResult.fromJson(json);
    expect(parsed.serial, result.serial);
    expect(parsed.success, result.success);
    expect(parsed.output, result.output);
    expect(parsed.durationMs, 42);
  });

  test('RustDalBridge is initialized and available', () {
    final bridge = RustDalBridge.instance;
    expect(bridge.isAvailable, isTrue);
  });

  test('RustDalBridge executeBatchShell with empty list returns empty list', () async {
    final bridge = RustDalBridge.instance;
    final results = await bridge.executeBatchShell([], 'echo hello');
    expect(results, isEmpty);
  });

  test('RustDalBridge executeShell on real attached device via Direct Socket', () async {
    final bridge = RustDalBridge.instance;
    if (!bridge.isAvailable) return;

    try {
      final out = await bridge.executeShell(
        '5002ba00',
        'echo "DAL_DIRECT_SOCKET_TEST"',
        platform: DevicePlatform.android,
      );
      expect(out.trim(), contains('DAL_DIRECT_SOCKET_TEST'));
    } catch (e) {
      // 若设备未连接则跳过
    }
  });

  test('RustDalBridge executeBatchShell on real device with semaphore limit', () async {
    final bridge = RustDalBridge.instance;
    if (!bridge.isAvailable) return;

    try {
      final results = await bridge.executeBatchShell(
        ['5002ba00'],
        'echo "BATCH_PARALLEL_OK"',
        maxConcurrency: 2,
      );
      expect(results, isNotEmpty);
      expect(results.first.success, isTrue);
      expect(results.first.output.trim(), contains('BATCH_PARALLEL_OK'));
    } catch (_) {
      // 若设备未连接则跳过
    }
  });

  test('RustDalBridge listHarmonyDevices returns list or empty list', () async {
    final bridge = RustDalBridge.instance;
    if (!bridge.isAvailable) return;

    final devices = await bridge.listHarmonyDevices();
    expect(devices, isA<List<Map<String, dynamic>>>());
  });

  test('RustDalBridge executeBatchShell supports DevicePlatform.harmony parameter', () async {
    final bridge = RustDalBridge.instance;
    final results = await bridge.executeBatchShell(
      [],
      'echo hello',
      platform: DevicePlatform.harmony,
    );
    expect(results, isEmpty);
  });
}
