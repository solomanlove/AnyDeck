import 'dart:ffi';
import 'dart:io';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/dal/device_driver.dart';
import 'package:any_deck/core/dal/rust_dal_bridge.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通过受控的原生等待验证设备发现和脚本执行期间主 Isolate 仍能处理事件。
void main() {
  if (!Platform.isMacOS && !Platform.isLinux) return;

  late Directory temporary;
  late RustDalBridge bridge;
  late RustDalBridge legacyBridge;
  late DynamicLibrary fixture;

  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('anydeck-dal-test-');
    addTearDown(() => temporary.delete(recursive: true));
    Future<String> compile(String name, {bool legacy = false}) async {
      final output = '${temporary.path}/$name';
      final result = await Process.run('cc', [
        Platform.isMacOS ? '-dynamiclib' : '-shared',
        '-fPIC',
        if (legacy) '-DANYDECK_LEGACY_DAL',
        'test/fixtures/tool_path_dal_stub.c',
        '-o',
        output,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return output;
    }

    final path = await compile('timed-dal');
    fixture = DynamicLibrary.open(path);
    bridge = RustDalBridge.open(path);
    legacyBridge = RustDalBridge.open(
      await compile('legacy-dal', legacy: true),
    );
  });

  Future<T> whileMainIsolateResponds<T>(Future<T> Function() operation) async {
    final hold = fixture.lookupFunction<Void Function(), void Function()>(
      'test_hold_next_call',
    );
    final blocked = fixture.lookupFunction<Int32 Function(), int Function()>(
      'test_is_native_blocked',
    );
    final release = fixture.lookupFunction<Void Function(), void Function()>(
      'test_release_call',
    );
    hold();
    var completed = false;
    final result = operation().whenComplete(() => completed = true);
    result.ignore();
    try {
      final watch = Stopwatch()..start();
      while (!completed &&
          blocked() == 0 &&
          watch.elapsed < const Duration(seconds: 2)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(blocked(), 1);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
    } finally {
      release();
    }
    return result;
  }

  test('鸿蒙设备发现等待原生结果时主 Isolate 可继续处理事件', () async {
    final service = HdcService(bridge: bridge);
    final devices = await whileMainIsolateResponds(service.listDevices);
    expect(devices.single.id, 'harmony-fixture');
    expect(devices.single.isHarmony, isTrue);
  });

  test('iOS 设备发现等待原生结果时主 Isolate 可继续处理事件', () async {
    final service = IosDeviceService(bridge: bridge);
    final devices = await whileMainIsolateResponds(service.listDevices);
    expect(devices.single.id, 'ios-fixture');
    expect(devices.single.isIos, isTrue);
  });

  test('Android 批量脚本所用的 executeShell 等待原生结果时主 Isolate 可继续处理事件', () async {
    final output = await whileMainIsolateResponds(
      () => bridge.executeShell(
        'android-fixture',
        'echo fixture',
        platform: DevicePlatform.android,
      ),
    );
    expect(output, 'native-path-used');
  });

  test('鸿蒙 Shell 在后台执行并把调用方的微秒 timeout 交给原生 ABI', () async {
    const timeout = Duration(seconds: 2, microseconds: 123);
    final service = _RecordingHdc(bridge);
    final result = await whileMainIsolateResponds(
      () => service.shell('harmony-fixture', 'echo fixture', timeout: timeout),
    );
    final nativeTimeout = fixture
        .lookupFunction<Uint64 Function(), int Function()>(
          'test_shell_timeout',
        );
    expect(nativeTimeout(), timeout.inMicroseconds);
    expect(result.stdout, 'native-path-used');
    expect(service.cliTimeouts, isEmpty);
  });

  test('原生 Shell 用完预算后报告超时，CLI 不重复执行命令', () async {
    final service = _RecordingHdc(bridge);
    final result = await service.shell(
      'harmony-fixture',
      'test-native-timeout',
      timeout: const Duration(milliseconds: 50),
    );
    expect(result.exitCode, 124);
    expect(service.cliTimeouts, isEmpty);
  });

  test('原生 Shell 提前失败时，CLI 使用调用方剩余的预算', () async {
    const timeout = Duration(seconds: 2);
    final service = _RecordingHdc(bridge);
    final result = await service.shell(
      'harmony-fixture',
      'test-native-failure',
      timeout: timeout,
    );
    expect(result.stdout, 'cli-path-used');
    expect(service.cliTimeouts.single, greaterThan(Duration.zero));
    expect(service.cliTimeouts.single, lessThan(timeout));
  });

  test('旧版动态库没有 timeout ABI 时，鸿蒙 Shell 直接使用 CLI', () async {
    const timeout = Duration(milliseconds: 123);
    final service = _RecordingHdc(legacyBridge);
    final result = await service.shell(
      'harmony-fixture',
      'echo fixture',
      timeout: timeout,
    );
    expect(legacyBridge.isAvailable, isTrue);
    expect(result.stdout, 'cli-path-used');
    expect(service.cliTimeouts, [timeout]);
  });
}

class _RecordingHdc extends HdcService {
  _RecordingHdc(RustDalBridge bridge) : super(bridge: bridge);

  final cliTimeouts = <Duration>[];

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    cliTimeouts.add(timeout);
    return const AdbResult(exitCode: 0, stdout: 'cli-path-used', stderr: '');
  }
}
