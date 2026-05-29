import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adb_manage/core/device_info/device_overview.dart';
import 'package:adb_manage/core/device_info/device_info_service.dart';
import 'package:adb_manage/core/adb/adb_service.dart';
import 'package:adb_manage/core/adb/adb_result.dart';

class StubAdbService extends AdbService {
  StubAdbService({this.shouldFail = false});

  final bool shouldFail;

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (shouldFail) {
      return const AdbResult(
        exitCode: 1,
        stdout: '',
        stderr: 'error: device offline',
      );
    }
    if (args.contains('get-serialno')) {
      return const AdbResult(exitCode: 0, stdout: '5002ba00', stderr: '');
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (shouldFail) {
      return const AdbResult(
        exitCode: 1,
        stdout: '',
        stderr: 'error: device offline',
      );
    }
    if (args.contains('getprop')) {
      return const AdbResult(
        exitCode: 0,
        stdout:
            '[ro.product.marketname]: [Redmi K40]\n'
            '[ro.product.brand]: [Redmi]\n'
            '[ro.product.model]: [M2012K11AC]\n'
            '[ro.product.cpu.abi]: [arm64-v8a]\n'
            '[ro.product.device]: [alioth]\n'
            '[ro.build.version.release]: [13]\n'
            '[ro.build.version.sdk]: [33]\n',
        stderr: '',
      );
    }
    if (args.contains('android_id')) {
      return const AdbResult(
        exitCode: 0,
        stdout: 'abcdef1234567890',
        stderr: '',
      );
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceOverview Serialization', () {
    test('toJson and fromJson are symmetrical', () {
      const overview = DeviceOverview(
        name: 'Redmi K40',
        brand: 'Redmi',
        model: 'M2012K11AC',
        serial: '5002ba00',
        androidId: 'abcdef1234567890',
        androidVersion: 'Android 13 (API 33)',
        kernelVersion: '4.19.157',
        processor: 'alioth 6 cores (arm64-v8a)',
        storage: '202.92G / 225.43G',
        memory: '11.24G',
        physicalResolution: '1080x2400 (440dpi)',
        resolution: '1080x2400 (440dpi)',
        logicalDensity: '2.75x (xxhdpi)',
        refreshRate: '120 Hz',
        fontScale: '1x',
        wifi: 'jie',
        wifiEnabled: true,
        ipAddress: '192.168.31.54',
        macAddress: '6c:f7:84:80:c9:33',
        airplaneModeEnabled: false,
        mobileDataEnabled: true,
        talkbackEnabled: false,
      );

      final json = overview.toJson();
      final decoded = DeviceOverview.fromJson(json);

      expect(decoded.name, overview.name);
      expect(decoded.brand, overview.brand);
      expect(decoded.model, overview.model);
      expect(decoded.serial, overview.serial);
      expect(decoded.androidId, overview.androidId);
      expect(decoded.androidVersion, overview.androidVersion);
      expect(decoded.kernelVersion, overview.kernelVersion);
      expect(decoded.processor, overview.processor);
      expect(decoded.storage, overview.storage);
      expect(decoded.memory, overview.memory);
      expect(decoded.physicalResolution, overview.physicalResolution);
      expect(decoded.resolution, overview.resolution);
      expect(decoded.logicalDensity, overview.logicalDensity);
      expect(decoded.refreshRate, overview.refreshRate);
      expect(decoded.fontScale, overview.fontScale);
      expect(decoded.wifi, overview.wifi);
      expect(decoded.wifiEnabled, overview.wifiEnabled);
      expect(decoded.ipAddress, overview.ipAddress);
      expect(decoded.macAddress, overview.macAddress);
      expect(decoded.airplaneModeEnabled, overview.airplaneModeEnabled);
      expect(decoded.mobileDataEnabled, overview.mobileDataEnabled);
      expect(decoded.talkbackEnabled, overview.talkbackEnabled);
    });
  });

  group('DeviceInfoService Cache & Fallback', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'should save to cache on success and load from cache on failure',
      () async {
        final onlineAdb = StubAdbService(shouldFail: false);
        final service = DeviceInfoService(onlineAdb);

        // 1. Load while online (saves to cache)
        final overview = await service.loadOverview('device1');
        expect(overview.name, 'Redmi K40');
        expect(overview.brand, 'Redmi');

        // 2. Load while offline (should fallback to cached value)
        final offlineAdb = StubAdbService(shouldFail: true);
        final offlineService = DeviceInfoService(offlineAdb);

        final cachedOverview = await offlineService.loadOverview('device1');
        expect(cachedOverview.name, 'Redmi K40');
        expect(cachedOverview.brand, 'Redmi');
      },
    );

    test('should throw error on failure if no cache exists', () async {
      final offlineAdb = StubAdbService(shouldFail: true);
      final service = DeviceInfoService(offlineAdb);

      expect(
        () => service.loadOverview('non_existent_device'),
        throwsException,
      );
    });
  });
}
