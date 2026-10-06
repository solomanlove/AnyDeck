import 'dart:async';
import 'dart:convert';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/device_info/device_info_service.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/ios/ios_overview_details.dart';
import 'package:any_deck/core/ios/ios_overview_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _info = {
  'ProductType': 'iPhone8,1',
  'DeviceName': '测试 iPhone',
  'SerialNumber': 'real-serial',
  'ProductVersion': '15.8.8',
  'BuildVersion': '19H422',
  'HardwareModel': 'N71AP',
  'CPUArchitecture': 'arm64',
  'WiFiAddress': '00:11:22:33:44:55',
  'instruments:hardwareInformation': {'numberOfCpus': 2},
  'instruments:networkInformation': {'en0': 'Wi-Fi'},
  'NonVolatileRAM': {'private-data': 'must-not-cache'},
};
const _disk = {'TotalBytes': 63968497664, 'FreeBytes': 40666718208};

/// 只返回命令桩，不调用任何设备 CLI。
class _Commands extends IosCommandService {
  final calls = <List<String>>[];
  final responses = <String, AdbResult>{};
  final pending = <String, Completer<AdbResult>>{};

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    calls.add(args);
    if (pending[args.first] case final value?) return value.future;
    return responses[args.first] ??
        AdbResult(
          exitCode: 0,
          stdout:
              '{"level":"WARN","msg":"agent is not running"}\n${jsonEncode(args.first == 'info' ? _info : _disk)}',
          stderr: '',
        );
  }
}

class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => const [
    RegisteredDevice(
      id: 'device-a',
      customName: '设备别名',
      status: 'device',
      isOnline: true,
      isIos: true,
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('读取型号、真实序列号和存储，保留 CPU/网络且不伪造其它读数', () async {
    final commands = _Commands();
    final result = await IosOverviewService(
      commands,
    ).load('device-a', fallbackName: 'fallback');
    expect(result.name, '测试 iPhone');
    expect(result.model, 'iPhone 6s (iPhone8,1)');
    expect(result.serial, 'real-serial');
    expect(result.androidVersion, 'iOS 15.8.8');
    expect(result.storage, '23.30 GB / 63.97 GB');
    expect(result.processor, 'arm64');
    expect(result.iosDetails?.cpuCores, 2);
    expect(result.iosDetails?.networkInterfaces, 'en0: Wi-Fi');
    expect(result.iosDetails?.buildVersion, '19H422');
    expect(result.macAddress, '00:11:22:33:44:55');
    for (final value in [
      result.memory,
      result.memoryUsed,
      result.kernelVersion,
      result.physicalResolution,
      result.logicalDensity,
      result.refreshRate,
      result.ipAddress,
    ]) {
      expect(value, '-');
    }
    expect(result.iosDetails?.partial, isFalse);
    expect(commands.calls, [
      ['info', '--udid=device-a'],
      ['diskspace', '--udid=device-a'],
    ]);
  });

  test('概览缓存只保存白名单，序列化和 copyWith 不丢 iOS 字段', () {
    final result = IosOverviewService.parse(
      _info,
      _disk,
      fallbackName: 'fallback',
    );
    final encoded = jsonEncode(result.toJson());
    expect(encoded, isNot(contains('NonVolatileRAM')));
    expect(encoded, isNot(contains('must-not-cache')));
    final restored = DeviceOverview.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );
    expect(restored.copyWith(name: 'alias').iosDetails?.hardwareModel, 'N71AP');
    expect(DeviceOverview.fromJson({}).iosDetails, isNull);
  });

  test('未知型号保持真实标识，不套用 iPhone 6s 的规格', () {
    final result = IosOverviewService.parse(
      {..._info, 'ProductType': 'iPhone99,9'},
      _disk,
      fallbackName: 'fallback',
    );
    expect(result.model, 'iPhone99,9');
    expect(IosModelSpec.byProductType[result.iosDetails?.productType], isNull);
  });

  test('单项失败保留成功字段，日志本身不能当作设备数据', () async {
    final commands = _Commands();
    commands.responses['info'] = const AdbResult(
      exitCode: 0,
      stdout: '{"level":"WARN","msg":"no data"}',
      stderr: '',
    );
    final result = await IosOverviewService(
      commands,
    ).load('device-a', fallbackName: 'fallback', fallbackVersion: 'iOS 15.8.8');
    expect(result.name, 'fallback');
    expect(result.androidVersion, 'iOS 15.8.8');
    expect(result.serial, '-');
    expect(result.storage, '23.30 GB / 63.97 GB');
    expect(result.iosDetails?.partial, isTrue);
    commands.responses.clear();
    commands.responses['diskspace'] = const AdbResult(
      exitCode: 124,
      stdout: '',
      stderr: 'timeout',
    );
    final partial = await IosOverviewService(
      commands,
    ).load('device-a', fallbackName: 'fallback');
    expect(partial.serial, 'real-serial');
    expect(partial.storage, '-');
    expect(partial.iosDetails?.partial, isTrue);
  });

  test('无效或缺失容量不显示负数，零剩余空间是有效读数', () {
    for (final disk in [
      {'TotalBytes': 0, 'FreeBytes': 0},
      {'TotalBytes': 100, 'FreeBytes': -1},
      {'TotalBytes': 100, 'FreeBytes': 101},
      {'TotalBytes': 100},
    ]) {
      final result = IosOverviewService.parse(
        _info,
        disk,
        fallbackName: 'fallback',
      );
      expect(result.storage, '-');
      expect(result.iosDetails?.partial, isTrue);
    }
    expect(
      IosOverviewService.parse(_info, {
        'TotalBytes': 1000000000,
        'FreeBytes': 0,
      }, fallbackName: 'fallback').storage,
      '1.00 GB / 1.00 GB',
    );
  });

  test('两个查询独立并行启动', () async {
    final commands = _Commands();
    commands.pending['info'] = Completer();
    commands.pending['diskspace'] = Completer();
    final future = IosOverviewService(
      commands,
    ).load('device-a', fallbackName: 'fallback');
    expect(commands.calls, hasLength(2));
    commands.pending['diskspace']!.complete(
      AdbResult(exitCode: 0, stdout: jsonEncode(_disk), stderr: ''),
    );
    commands.pending['info']!.complete(
      AdbResult(exitCode: 0, stdout: jsonEncode(_info), stderr: ''),
    );
    expect((await future).iosDetails?.partial, isFalse);
  });

  test('iOS Provider 接入新服务，刷新重新查询，离线缓存保留详细数据', () async {
    final commands = _Commands();
    final cache = DeviceInfoService(AdbService());
    final container = ProviderContainer(
      overrides: [
        iosCommandServiceProvider.overrideWithValue(commands),
        deviceInfoServiceProvider.overrideWithValue(cache),
        deviceRegistryProvider.overrideWith(_Registry.new),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      deviceOverviewProvider('device-a'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final first = await container.read(
      deviceOverviewProvider('device-a').future,
    );
    expect(first.serial, 'real-serial');
    expect(first.name, '设备别名');
    expect(
      (await cache.loadFromCache('device-a'))?.iosDetails?.buildVersion,
      '19H422',
    );
    container.invalidate(deviceOverviewProvider('device-a'));
    await container.read(deviceOverviewProvider('device-a').future);
    expect(commands.calls, hasLength(4));
  });

  const udid = String.fromEnvironment('IOS_OVERVIEW_UDID');
  if (udid.isNotEmpty) {
    test('真机只读查询返回型号、序列号、CPU 和有效存储', () async {
      final overview = await IosOverviewService(
        IosCommandService(),
      ).load(udid, fallbackName: 'iPhone');
      expect(overview.iosDetails?.partial, isFalse);
      expect(overview.deviceCode, isNot('-'));
      expect(overview.serial, isNot(anyOf('-', udid)));
      expect(overview.processor, isNot('-'));
      expect(overview.storage, contains(' GB / '));
    });
  }
}
