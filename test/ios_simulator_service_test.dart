import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/emulator/ios/ios_simulator_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录命令调用，用临时目录模拟当前 Xcode 的应用布局。
class _SimulatorService extends IosSimulatorService {
  _SimulatorService({required super.runProcess});

  @override
  bool get isSupported => true;
}

void main() {
  const udid = '12345678-1234-4321-8567-123456789ABC';
  late Directory temp;
  late String contents;
  late String simctlPath;
  late String hub;
  late String legacyApp;
  late List<List<String>> calls;
  late IosSimulatorService service;
  late int bootExitCode;
  late int openExitCode;
  late Completer<ProcessResult>? bootResult;
  late Completer<void> bootStarted;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('anydeck-ios-simulator-');
    contents = '${temp.path}/Custom Xcode.app/Contents';
    simctlPath = '$contents/Developer/usr/bin/simctl';
    hub = '$contents/Applications/DeviceHub.app';
    legacyApp = '$contents/Developer/Applications/Simulator.app';
    calls = [];
    bootExitCode = 0;
    openExitCode = 0;
    bootResult = null;
    bootStarted = Completer<void>();
    service = _SimulatorService(
      runProcess: (executable, args, {required timeout}) async {
        calls.add([executable, ...args]);
        if (args.first == '--find') {
          return ProcessResult(0, 0, '$simctlPath\n', '');
        }
        if (executable == '/usr/bin/open') {
          return ProcessResult(0, openExitCode, '', '');
        }
        expect(timeout, const Duration(minutes: 2));
        bootStarted.complete();
        if (bootResult != null) return bootResult!.future;
        return ProcessResult(0, bootExitCode, '', '');
      },
    );
  });

  tearDown(() => temp.delete(recursive: true));

  test('等待设备启动就绪后，通过 Device Hub 显示对应窗口', () async {
    await Directory(hub).create(recursive: true);
    bootResult = Completer<ProcessResult>();
    final launching = service.bootSimulator(udid);
    await bootStarted.future;
    expect(calls, [
      ['xcrun', 'simctl', 'bootstatus', udid, '-b'],
    ]);
    bootResult!.complete(ProcessResult(0, 0, '', ''));
    expect(await launching, isTrue);
    expect(calls.skip(1), [
      ['xcrun', '--find', 'simctl'],
      ['/usr/bin/open', '-a', hub, 'devices://device/open?id=$udid'],
    ]);
  });

  test('已启动设备直接打开窗口，通用入口打开同一套 Xcode 的 Device Hub', () async {
    await Directory(hub).create(recursive: true);
    expect(await service.showSimulatorWindow(udid), isTrue);
    expect(await service.openSimulatorApp(), isTrue);
    expect(calls, [
      ['xcrun', '--find', 'simctl'],
      ['/usr/bin/open', '-a', hub, 'devices://device/open?id=$udid'],
      ['xcrun', '--find', 'simctl'],
      ['/usr/bin/open', '-a', hub],
    ]);
  });

  test('旧版 Xcode 使用对应路径的 Simulator.app', () async {
    await Directory(legacyApp).create(recursive: true);
    expect(await service.showSimulatorWindow(udid), isTrue);
    expect(await service.openSimulatorApp(), isTrue);
    expect(calls, [
      ['xcrun', '--find', 'simctl'],
      ['/usr/bin/open', '-a', legacyApp, '--args', '-CurrentDeviceUDID', udid],
      ['xcrun', '--find', 'simctl'],
      ['/usr/bin/open', '-a', legacyApp],
    ]);
  });

  test('设备启动失败时不发送窗口请求', () async {
    await Directory(hub).create(recursive: true);
    bootExitCode = 1;
    expect(await service.bootSimulator(udid), isFalse);
    expect(calls, [
      ['xcrun', 'simctl', 'bootstatus', udid, '-b'],
    ]);
  });

  test('找不到窗口应用或打开命令失败时返回失败', () async {
    expect(await service.showSimulatorWindow(udid), isFalse);
    expect(calls, [
      ['xcrun', '--find', 'simctl'],
    ]);
    await Directory(hub).create(recursive: true);
    openExitCode = 1;
    expect(await service.showSimulatorWindow(udid), isFalse);
    expect(calls.last.first, '/usr/bin/open');
  });
}
