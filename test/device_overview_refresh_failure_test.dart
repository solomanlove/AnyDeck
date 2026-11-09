import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/device_info/device_info_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模拟 getprop 仍成功，而分组 Shell 或 dumpsys 在刷新时独立失败。
class _RefreshAdb extends AdbService {
  final failed = <String>{};
  final unsupportedTail = <String>{};

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final command = args.skip(3).join(' ');
    final group = command.contains('===UNAME===')
        ? 'basic'
        : command.contains('===FONTSCALE===')
        ? 'settings'
        : command;
    if (failed.contains(group)) {
      return const AdbResult(exitCode: 124, stdout: '', stderr: 'timeout');
    }
    final output = switch (group) {
      'getprop' =>
        '[ro.product.model]: [AnyDeck test phone]\n'
            '[ro.build.version.release]: [16]\n[ro.build.version.sdk]: [36]',
      'basic' =>
        '===UNAME===\n6.1-test\n===NPROC===\n8\n'
            '===WMSIZE===\nPhysical size: 1080x2400\n'
            '===WMDENSITY===\nPhysical density: 440\n'
            '===MEMINFO===\nMemTotal: 8388608 kB\nMemAvailable: 2097152 kB\n'
            '===DF===\nFilesystem 1K-blocks Used Available Use% Mounted on\n'
            '/dev/block/data 67108864 33554432 33554432 50% /data\n'
            '===BATTERY===\nstatus: 2\nlevel: 68\nscale: 100\n'
            '===IP===\ninet 192.0.2.10/24\n===DEVICESTATES===\n',
      'settings' =>
        '===FONTSCALE===\n1\n===WIFION===\n1\n'
            '===ANDROIDID===\n0123456789abcdef\n'
            '===VIEWATTRIBUTEINSPECTION===\n0\n',
      'dumpsys wifi' => 'mWifiInfo SSID: "AnyDeck test WiFi",',
      'dumpsys display' => 'mSupportedRefreshRates=[60, 120]',
      _ => 'fixture-serial',
    };
    return AdbResult(
      exitCode: unsupportedTail.contains(group) ? 1 : 0,
      stdout: output,
      stderr: '',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final group in [
    'basic',
    'settings',
    'dumpsys wifi',
    'dumpsys display',
  ]) {
    test('$group 超时不清空已展示的信息，也不更新缓存采集时间', () async {
      final adb = _RefreshAdb();
      final service = DeviceInfoService(adb);
      final original = await service.loadOverview('shared-device');
      final before = await service.loadCachedSnapshot('shared-device');
      expect(original.battery?.level, 68);
      expect(original.androidId, '0123456789abcdef');
      expect(original.memory, '8.00G');
      expect(original.wifi, 'AnyDeck test WiFi');
      expect(original.refreshRate, '120 Hz');
      adb.failed.add(group);

      final refreshed = await service.loadOverview('shared-device');
      final after = await service.loadCachedSnapshot('shared-device');
      expect(refreshed.toJson(), original.toJson());
      expect(after?.overview.toJson(), original.toJson());
      expect(after?.collectedAt, before?.collectedAt);
    });
  }

  test('没有缓存时，部分命令超时不能作为成功概览保存', () async {
    final service = DeviceInfoService(_RefreshAdb()..failed.add('basic'));
    await expectLater(service.loadOverview('new-device'), throwsException);
    expect(await service.loadCachedSnapshot('new-device'), isNull);
  });

  test('禁用缓存回退时，部分命令失败必须向调用方报告', () async {
    final adb = _RefreshAdb();
    final service = DeviceInfoService(adb);
    await service.loadOverview('shared-device');
    adb.failed.add('settings');
    await expectLater(
      service.loadOverview('shared-device', allowCachedFallback: false),
      throwsException,
    );
  });

  test('旧系统不支持脚本末尾可选命令时，已采集数据仍可展示和缓存', () async {
    final adb = _RefreshAdb()..unsupportedTail.addAll(['basic', 'settings']);
    final service = DeviceInfoService(adb);
    final overview = await service.loadOverview('legacy-device');
    expect(overview.battery?.level, 68);
    expect(overview.androidId, '0123456789abcdef');
    expect(
      (await service.loadCachedSnapshot('legacy-device'))?.collectedAt,
      isNotNull,
    );
  });
}
