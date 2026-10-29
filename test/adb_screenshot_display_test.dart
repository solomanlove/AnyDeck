import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/adb/screenshot_display_selector.dart';
import 'package:flutter_test/flutter_test.dart';

// 基于 SM-F9710 的 DisplayManager 字段，裁去刷新率、亮度等无关内容。
const _unfolded = '''
DISPLAY MANAGER (dumpsys display)
  mViewports=[DisplayViewport{type=INTERNAL, isActive=true, displayId=0, uniqueId='local:4630947004648141459'}]
Display Devices: size=3
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:4630947123231501204", 1248 x 1972, type INTERNAL, state OFF, committedState OFF, FLAG_ALLOWED_TO_BE_DEFAULT_DISPLAY}
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:4630947004648141459", 2448 x 1848, supportedModes [{id=1, width=2448, height=1848}], type INTERNAL, state ON, committedState ON, FLAG_ALLOWED_TO_BE_DEFAULT_DISPLAY}
  DisplayDeviceInfo{"scrcpy": uniqueId="virtual:com.android.shell,2000,scrcpy,8", 814 x 1080, type VIRTUAL, state ON, committedState UNKNOWN}
Logical Displays: size=3
    mDisplayId=0
    mPrimaryDisplayDevice=内置屏幕(local:4630947004648141459)
    mDisplayId=1
    mPrimaryDisplayDevice=内置屏幕(local:4630947123231501204)
''';

// 折叠后外屏启用，逻辑主屏与 physical displayId 的对应关系随之改变。
const _folded = '''
Display Devices: size=2
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:4630947004648141459", 2448 x 1848, type INTERNAL, state OFF, committedState OFF}
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:4630947123231501204", 1248 x 1972, type INTERNAL, state ON, committedState ON}
Logical Displays: size=2
    mDisplayId=0
    mPrimaryDisplayDevice=内置屏幕(local:4630947123231501204)
''';

const _single = '''
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:4630946693002713985", 1080 x 2340, type INTERNAL, state ON, committedState ON}
''';

const _png = [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0,
  0,
  0,
  0,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];

/// 模拟二进制截图双流、退出失败与超时清理，不启动真实 adb。
class _ScreenshotProcess implements Process {
  _ScreenshotProcess({this.code = 0, this.hang = false});

  final int code;
  final bool hang;
  final ended = Completer<int>();
  bool killed = false;

  @override
  Stream<List<int>> get stdout => Stream.value([
    ...utf8.encode('[Warning] Multiple displays were found!\n'),
    ..._png,
  ]);

  @override
  Stream<List<int>> get stderr => Stream.value(
    utf8.encode(code == 0 ? '' : 'screencap: Permission denied'),
  );

  @override
  Future<int> get exitCode => hang ? ended.future : Future.value(code);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!ended.isCompleted) ended.complete(-1);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 记录选屏探测与实际截图参数，用连续快照验证不会缓存折叠状态。
class _ScreenshotAdb extends AdbService {
  String dump = _unfolded;
  int probeCode = 0;
  Duration probeDelay = Duration.zero;
  final probes = <List<String>>[];
  final captures = <List<String>>[];
  final probeTimeouts = <Duration>[];
  _ScreenshotProcess process = _ScreenshotProcess();

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    probes.add(args);
    probeTimeouts.add(timeout);
    if (probeDelay > Duration.zero) await Future<void>.delayed(probeDelay);
    return AdbResult(
      exitCode: probeCode,
      stdout: dump,
      stderr: probeCode == 0 ? '' : 'Display probe unavailable',
    );
  }

  @override
  Future<Process> start(List<String> args) async {
    captures.add(args);
    return process;
  }
}

void main() {
  group('ScreenshotDisplaySelector', () {
    test('展开选择点亮内屏，忽略外屏、viewport 与 scrcpy 虚拟屏', () {
      expect(
        ScreenshotDisplaySelector.select(_unfolded),
        '4630947004648141459',
      );
    });

    test('折叠选择外屏，使用物理 ID 而非逻辑 ID 0', () {
      expect(ScreenshotDisplaySelector.select(_folded), '4630947123231501204');
    });

    test('普通单屏与旧 BUILT_IN 类型均可解析', () {
      expect(ScreenshotDisplaySelector.select(_single), '4630946693002713985');
      expect(
        ScreenshotDisplaySelector.select(
          _single.replaceAll('INTERNAL', 'BUILT_IN'),
        ),
        '4630946693002713985',
      );
    });

    test('多个内置屏 ON 时优先主屏，不取枚举的第一个屏幕', () {
      expect(
        ScreenshotDisplaySelector.select(
          _unfolded.replaceAll('state OFF', 'state ON'),
        ),
        '4630947004648141459',
      );
    });

    test('主屏 OFF 时选择另一个 ON 内置屏，支持 CRLF', () {
      final dump = _unfolded
          .replaceFirst('state OFF', 'state ON')
          .replaceFirst(
            'type INTERNAL, state ON, committedState ON, FLAG',
            'type INTERNAL, state OFF, committedState ON, FLAG',
          );
      expect(
        ScreenshotDisplaySelector.select(dump.replaceAll('\n', '\r\n')),
        '4630947123231501204',
      );
    });

    test('忽略外接屏、虚拟屏与非 ON 内置屏，不将 committedState 当作当前状态', () {
      const dump = '''
  DisplayDeviceInfo{"HDMI": uniqueId="local:91", type EXTERNAL, state ON}
  DisplayDeviceInfo{"virtual": uniqueId="virtual:92", type VIRTUAL, state ON}
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:93", type INTERNAL, state OFF, committedState ON}
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:94", type INTERNAL, state DOZE, committedState ON}
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:95", type INTERNAL, state ON_SUSPEND, committedState ON}
''';
      expect(ScreenshotDisplaySelector.select(dump), isNull);
    });

    test('不将 uint64 物理 ID 截断成有符号整数', () {
      expect(
        ScreenshotDisplaySelector.select(
          _single.replaceAll('4630946693002713985', '18446744073709551614'),
        ),
        '18446744073709551614',
      );
    });

    test('缺失、未知或非数字 local ID 时安全回退', () {
      for (final dump in [
        '',
        'Permission denied',
        _single.replaceAll('local:', 'other:'),
        _single.replaceAll('4630946693002713985', 'broken'),
      ]) {
        expect(ScreenshotDisplaySelector.select(dump), isNull);
      }
    });
  });

  group('AdbService 自动选屏截图', () {
    test('同一服务展开→折叠→展开每次重读状态，并清理 PNG 警告前缀', () async {
      final adb = _ScreenshotAdb();
      for (final dump in [_unfolded, _folded, _unfolded]) {
        adb.dump = dump;
        expect(await adb.captureScreenshot('samsung'), _png);
      }
      expect(
        adb.probes,
        List.filled(3, ['-s', 'samsung', 'shell', 'dumpsys', 'display']),
      );
      expect(adb.captures.map((args) => args.last), [
        '4630947004648141459',
        '4630947123231501204',
        '4630947004648141459',
      ]);
      expect(adb.captures.first, [
        '-s',
        'samsung',
        'exec-out',
        'screencap',
        '-p',
        '-d',
        '4630947004648141459',
      ]);
      expect(adb.probeTimeouts, List.filled(3, const Duration(seconds: 3)));
    });

    test('不同设备分别探测，USB 和 TCP ID 安全传递', () async {
      final adb = _ScreenshotAdb();
      await adb.captureScreenshot('R5GL6378JMH');
      adb.dump = _single;
      await adb.captureScreenshot('192.168.1.244:5555');
      expect(adb.probes.last[1], '192.168.1.244:5555');
      expect(adb.captures.last[1], '192.168.1.244:5555');
      expect(adb.captures.last.last, '4630946693002713985');
    });

    test('探测超时、权限失败或未知输出均保留原截图路径', () async {
      for (final code in [0, 1, 124]) {
        final adb = _ScreenshotAdb()..probeCode = code;
        if (code == 0) adb.dump = 'Legacy display output';
        expect(await adb.captureScreenshot('old-device'), _png);
        expect(adb.captures.single, [
          '-s',
          'old-device',
          'exec-out',
          'screencap',
          '-p',
        ]);
      }
    });

    test('截图失败保留原始错误，不误报为成功', () async {
      final adb = _ScreenshotAdb()..process = _ScreenshotProcess(code: 1);
      await expectLater(
        adb.captureScreenshot('samsung'),
        throwsA(
          isA<AdbException>().having(
            (error) => error.message,
            'message',
            contains('Permission denied'),
          ),
        ),
      );
    });

    test('截图超时终止进程，短预算探测不超过总预算的四分之一', () async {
      final adb = _ScreenshotAdb()..process = _ScreenshotProcess(hang: true);
      await expectLater(
        adb.captureScreenshot(
          'samsung',
          timeout: const Duration(milliseconds: 40),
        ),
        throwsA(
          isA<AdbException>().having(
            (error) => error.message,
            'message',
            contains('超时'),
          ),
        ),
      );
      expect(adb.process.killed, isTrue);
      expect(adb.probeTimeouts.single, const Duration(milliseconds: 10));
    });

    test('探测耗尽总预算后不再启动截图进程', () async {
      final adb = _ScreenshotAdb()
        ..probeDelay = const Duration(milliseconds: 30);
      await expectLater(
        adb.captureScreenshot(
          'samsung',
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<AdbException>()),
      );
      expect(adb.captures, isEmpty);
    });
  });
}
