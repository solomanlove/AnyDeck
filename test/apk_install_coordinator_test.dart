import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/window/apk/apk_open_coordinator.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/apps/app_management_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';

class _Adb extends AdbService {
  _Adb() : super(executable: 'unused');
  List<AdbDevice> devices = const [
    AdbDevice(id: 'target-serial', status: 'device'),
  ];
  @override
  Future<List<AdbDevice>> listDevices() async => devices;
}

class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [];
}

class _Apps extends AppManagementService {
  _Apps(super.adb);
  final loadGate = Completer<List<AdbPackage>?>();
  final installations = <String>[];
  AdbResult result = const AdbResult(
    exitCode: 0,
    stdout: 'Success',
    stderr: '',
  );
  int refreshes = 0;
  int saves = 0;
  @override
  Future<AdbResult> installApk(String deviceId, String apkPath) async {
    installations.add(deviceId);
    return result;
  }

  @override
  Future<List<AdbPackage>?> loadPackageCache(String deviceId) =>
      loadGate.future;
  @override
  Future<AdbPackage?> getSinglePackageInfo(
    String deviceId,
    String packageName,
  ) async {
    refreshes++;
    return AdbPackage(name: packageName);
  }

  @override
  Future<void> savePackageCache(
    String deviceId,
    List<AdbPackage> packages,
  ) async {
    saves++;
  }
}

void main() {
  late Directory dir;
  late File apk;
  late _Adb adb;
  late _Apps apps;
  late ProviderContainer container;
  late ApkOpenCoordinator coordinator;
  late Map<String, dynamic> args;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('apk-install-test-');
    apk = File('${dir.path}/app.apk');
    await apk.writeAsString('fixture');
    final stat = await apk.stat();
    args = {
      'requestId': 'one',
      'serial': 'target-serial',
      'path': apk.path,
      'packageName': 'test.new.app',
      'size': stat.size,
      'modified': stat.modified.microsecondsSinceEpoch,
    };
    adb = _Adb();
    apps = _Apps(adb);
    container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(adb),
        appManagementServiceProvider.overrideWithValue(apps),
        deviceRegistryProvider.overrideWith(_Registry.new),
      ],
    );
    coordinator = ApkOpenCoordinator(container);
  });
  tearDown(() async {
    container.dispose();
    await dir.delete(recursive: true);
  });

  test('安装锁定 serial，并等待初次缓存加载后刷新已安装包', () async {
    final result = coordinator.handleWindowCall(
      MethodCall('apk_install', args),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(apps.installations, ['target-serial']);
    expect(apps.refreshes, 0);
    apps.loadGate.complete([const AdbPackage(name: 'cached.old.app')]);
    expect((await result)['success'], true);
    expect(apps.refreshes, 1);
    expect(apps.saves, 1);
    expect(
      container
          .read(packagesProvider('target-serial'))
          .requireValue
          .map((p) => p.name),
      contains('test.new.app'),
    );
  });
  test('离线不安装，不自动切换到另一个在线设备', () async {
    adb.devices = const [
      AdbDevice(id: 'target-serial', status: 'offline'),
      AdbDevice(id: 'other', status: 'device'),
    ];
    final result = await coordinator.handleWindowCall(
      MethodCall('apk_install', args),
    );
    expect(result['error'], 'apkDeviceUnavailable');
    expect(apps.installations, isEmpty);
  });
  test('文件替换后拒绝安装，要求重新解析', () async {
    await apk.writeAsString('different content');
    final result = await coordinator.handleWindowCall(
      MethodCall('apk_install', args),
    );
    expect(result['error'], 'apkFileChanged');
    expect(apps.installations, isEmpty);
  });
  test('签名冲突保留原始错误且不刷新或卸载', () async {
    apps.result = const AdbResult(
      exitCode: 1,
      stdout: '',
      stderr: 'INSTALL_FAILED_UPDATE_INCOMPATIBLE',
    );
    final result = await coordinator.handleWindowCall(
      MethodCall('apk_install', args),
    );
    expect(result['success'], false);
    expect(result['error'], contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE'));
    expect(apps.refreshes, 0);
    expect(apps.installations, ['target-serial']);
  });
}
