import 'dart:io';

import 'package:any_deck/core/process/host_platform_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_process.dart';

/// 故意忽略 TERM，验证超时后进一步强制回收启动器。
class _StubbornProcess extends ControlledProcess {
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (signal == ProcessSignal.sigkill) finish(-1);
    return true;
  }
}

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('anydeck host launcher ');
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    for (final terminal in [false, true]) {
      test('$platform ${terminal ? '终端' : '目录'}检查启动器退出码并保持路径独立传参', () async {
        var exitCode = 0;
        final calls = <(String, List<String>, String?)>[];
        final host = HostPlatformService(
          platform: platform,
          processStarter: (executable, arguments, {workingDirectory}) async {
            calls.add((executable, arguments, workingDirectory));
            return ControlledProcess()..finish(exitCode);
          },
        );
        Future<bool> launch() => terminal
            ? host.openTerminal(temporary.path)
            : host.openDirectory(temporary.path);
        expect(await launch(), isTrue);
        exitCode = 27;
        expect(await launch(), isFalse);
        expect(calls, hasLength(2));
        for (final call in calls) {
          if (!terminal) {
            expect(call.$2, [temporary.path]);
          } else if (platform == TargetPlatform.macOS) {
            expect(call.$1, 'open');
            expect(call.$2, ['-a', 'Terminal', temporary.path]);
          } else {
            expect(call.$3, temporary.path);
          }
        }
      });
    }
  }

  test('路径缺失或平台不支持时不启动任何系统进程', () async {
    var launches = 0;
    final host = HostPlatformService(
      platform: TargetPlatform.macOS,
      processStarter: (_, _, {workingDirectory}) async {
        launches++;
        return ControlledProcess()..finish();
      },
    );
    expect(await host.openDirectory('${temporary.path}/missing'), isFalse);
    expect(await host.openTerminal('${temporary.path}/missing'), isFalse);
    expect(launches, 0);
    final unsupported = HostPlatformService(platform: TargetPlatform.android);
    expect(await unsupported.openDirectory(temporary.path), isFalse);
    expect(await unsupported.openTerminal(temporary.path), isFalse);
  });

  test('启动器抛出异常时返回失败', () async {
    final host = HostPlatformService(
      platform: TargetPlatform.macOS,
      processStarter: (executable, arguments, {workingDirectory}) async =>
          throw const ProcessException('launcher', [], 'not found'),
    );
    expect(await host.openDirectory(temporary.path), isFalse);
    expect(await host.openTerminal(temporary.path), isFalse);
  });

  for (final terminal in [false, true]) {
    test('短命启动器无响应时返回失败并执行 TERM / KILL 回收 $terminal', () async {
      final process = _StubbornProcess();
      final host = HostPlatformService(
        platform: TargetPlatform.macOS,
        launchTimeout: const Duration(milliseconds: 5),
        terminateTimeout: const Duration(milliseconds: 5),
        processStarter: (_, _, {workingDirectory}) async => process,
      );
      final result = terminal
          ? await host.openTerminal(temporary.path)
          : await host.openDirectory(temporary.path);
      expect(result, isFalse);
      expect(process.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
    });
  }

  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    test('$platform 长驻系统应用完成启动后不被超时回收', () async {
      final process = ControlledProcess();
      final host = HostPlatformService(
        platform: platform,
        startupGrace: const Duration(milliseconds: 5),
        processStarter: (_, _, {workingDirectory}) async => process,
      );
      expect(await host.openDirectory(temporary.path), isTrue);
      expect(process.signals, isEmpty);
      expect(process.output.hasListener, isTrue);
      expect(process.errors.hasListener, isTrue);
      process.finish();
      if (platform == TargetPlatform.linux) {
        final terminal = ControlledProcess();
        final terminalHost = HostPlatformService(
          platform: platform,
          startupGrace: const Duration(milliseconds: 5),
          processStarter: (_, _, {workingDirectory}) async => terminal,
        );
        expect(await terminalHost.openTerminal(temporary.path), isTrue);
        expect(terminal.signals, isEmpty);
        expect(terminal.output.hasListener, isTrue);
        expect(terminal.errors.hasListener, isTrue);
        terminal.finish();
      }
    });
  }
}
