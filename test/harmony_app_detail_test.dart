import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/apps/app_management_service.dart';
import 'package:any_deck/core/apps/harmony_app_detail.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHarmonyHdcService extends HdcService {
  _FakeHarmonyHdcService(this.result) : super(executable: 'hdc');

  final AdbResult result;
  final commands = <String>[];

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add('$deviceId:$command');
    return result;
  }
}

const _dumpOutput = '''
com.example.harmony:
{
  "name": "com.example.harmony",
  "versionName": "1.2.3",
  "versionCode": 123,
  "vendor": "example",
  "compatibleVersion": 50000012,
  "targetVersion": 60101024,
  "releaseType": "Release",
  "installTime": 1700000000000,
  "updateTime": 1700000010000,
  "applicationInfo": {
    "bundleName": "com.example.harmony",
    "organization": "Example Ltd.",
    "compileSdkVersion": "6.0.1.24",
    "appProvisionType": "release",
    "appDistributionType": "app_gallery",
    "cpuAbi": "arm64-v8a",
    "codePath": "/data/app/com.example.harmony",
    "fingerprint": "ABCDEF",
    "enabled": true,
    "isSystemApp": false
  },
  "hapModuleInfos": [
    {
      "moduleName": "entry",
      "packageName": "entry",
      "mainElementName": "EntryAbility",
      "hapPath": "/data/app/com.example.harmony/entry.hap",
      "moduleType": 1,
      "deviceTypes": ["phone", "tablet"],
      "nativeLibraryFileNames": ["libexample.so"],
      "abilityInfos": [
        {
          "name": "EntryAbility",
          "moduleName": "entry",
          "srcEntrance": "./ets/entryability/EntryAbility.ets",
          "enabled": true,
          "visible": true,
          "permissions": ["ohos.permission.INTERNET"],
          "skills": [{"actions": ["action.system.home"], "entities": ["entity.system.home"]}]
        }
      ],
      "extensionInfos": [
        {
          "name": "BackupExtensionAbility",
          "moduleName": "entry",
          "extensionTypeName": "backup",
          "enabled": true,
          "visible": false
        }
      ],
      "metadata": [{"name": "sample.key", "value": "sample.value"}]
    }
  ],
  "reqPermissionDetails": [
    {
      "name": "ohos.permission.INTERNET",
      "moduleName": "entry",
      "reason": "network",
      "usedScene": {"abilities": ["EntryAbility"], "when": "inuse"}
    }
  ]
}
''';

void main() {
  test('解析 bm dump 的应用、HAP、Ability、权限与元数据', () {
    final detail = HarmonyAppDetailParser.parse(_dumpOutput);

    expect(detail.bundleName, 'com.example.harmony');
    expect(detail.versionName, '1.2.3');
    expect(detail.targetApiVersion, 60101024);
    expect(detail.organization, 'Example Ltd.');
    expect(detail.modules, hasLength(1));
    expect(detail.modules.single.nativeLibraries, ['libexample.so']);
    expect(detail.abilities.single.name, 'EntryAbility');
    expect(detail.abilities.single.actions, ['action.system.home']);
    expect(detail.extensions.single.type, 'backup');
    expect(detail.permissions.single.when, 'inuse');
    expect(detail.metadata, {'sample.key': 'sample.value'});
  });

  test('bm dump 未返回 JSON 时判定为不支持分析', () {
    expect(
      () => HarmonyAppDetailParser.parse('[Fail] bundle not found'),
      throwsFormatException,
    );
  });

  test('鸿蒙详情服务只执行 HDC bm dump，不调用 ADB', () async {
    final hdc = _FakeHarmonyHdcService(
      const AdbResult(exitCode: 0, stdout: _dumpOutput, stderr: ''),
    );
    final service = AppManagementService(
      AdbService(executable: 'adb'),
      hdc: hdc,
    );

    final detail = await service.getHarmonyPackageDetailedInfo(
      'harmony-device',
      'com.example.harmony',
    );

    expect(detail.bundleName, 'com.example.harmony');
    expect(hdc.commands, ['harmony-device:bm dump -n com.example.harmony']);
  });

  test('非法 bundleName 在执行 HDC 前被拒绝', () async {
    final hdc = _FakeHarmonyHdcService(
      const AdbResult(exitCode: 0, stdout: _dumpOutput, stderr: ''),
    );
    final service = AppManagementService(
      AdbService(executable: 'adb'),
      hdc: hdc,
    );

    await expectLater(
      service.getHarmonyPackageDetailedInfo(
        'harmony-device',
        'com.example.app;rm -rf /',
      ),
      throwsA(isA<HarmonyAppAnalysisUnsupportedException>()),
    );
    expect(hdc.commands, isEmpty);
  });

  test('HDC bm dump 失败时返回不支持分析且不回退 ADB', () async {
    final hdc = _FakeHarmonyHdcService(
      const AdbResult(exitCode: 1, stdout: '', stderr: 'bundle not found'),
    );
    final service = AppManagementService(
      AdbService(executable: 'adb'),
      hdc: hdc,
    );

    await expectLater(
      service.getHarmonyPackageDetailedInfo(
        'harmony-device',
        'com.example.harmony',
      ),
      throwsA(isA<HarmonyAppAnalysisUnsupportedException>()),
    );
    expect(hdc.commands, ['harmony-device:bm dump -n com.example.harmony']);
  });
}
