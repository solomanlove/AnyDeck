import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 模拟器进程退出结果；保留有界日志供 UI 展示实际失败原因。
class EmulatorExit {
  const EmulatorExit(this.code, this.output);

  final int code;
  final String output;
}

/// 已创建的进程不代表 Android 已上线；由 Provider 结合 ADB 状态判断。
class EmulatorProcess {
  const EmulatorProcess({required this.exited, required this.output});

  final Future<EmulatorExit> exited;
  final String Function() output;

  /// 持续排空 stdout/stderr，分别保留最后 16,384 个字符，避免管道阻塞和日志无限增长。
  static Future<EmulatorProcess> start(
    String executable,
    String name, {
    Map<String, String>? environment,
    bool coldBoot = false,
  }) async {
    final process = await Process.start(executable, [
      '-avd',
      name,
      if (coldBoot) '-no-snapshot-load',
    ], environment: environment);
    unawaited(process.stdin.close());
    var stdoutTail = '';
    var stderrTail = '';
    String tail(String old, String chunk) {
      final next = old + chunk;
      return next.length > 16384 ? next.substring(next.length - 16384) : next;
    }

    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    final stdoutSubscription = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (chunk) => stdoutTail = tail(stdoutTail, chunk),
          onError: (Object error) => stdoutTail = tail(stdoutTail, '$error'),
          onDone: stdoutDone.complete,
        );
    final stderrSubscription = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (chunk) => stderrTail = tail(stderrTail, chunk),
          onError: (Object error) => stderrTail = tail(stderrTail, '$error'),
          onDone: stderrDone.complete,
        );
    String output() => [
      stderrTail.trim(),
      stdoutTail.trim(),
    ].where((value) => value.isNotEmpty).join('\n');

    Future<EmulatorExit> waitForExit() async {
      final code = await process.exitCode;
      try {
        // 部分子进程可能继承管道，退出后只等待有限时间收集末尾日志。
        await Future.wait([
          stdoutDone.future,
          stderrDone.future,
        ]).timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // 已退出主进程的诊断仍应及时交付。
      } finally {
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
      }
      return EmulatorExit(code, output());
    }

    // 模拟器由用户启动并独立使用，切换 Tab 不终止它；管道在退出时回收。
    return EmulatorProcess(exited: waitForExit(), output: output);
  }
}

/// 启动状态与错误语义；中文/英文文案由展示层解析。
class EmulatorLaunchState {
  const EmulatorLaunchState({
    this.starting = false,
    this.processAlive = false,
    this.errorKey,
    this.details = '',
    this.exitCode,
  });

  final bool starting;
  final bool processAlive;
  final String? errorKey;
  final String details;
  final int? exitCode;

  /// 进程存活但调试连接不可用，不应展示为启动失败。
  bool get isConnectionIssue => processAlive && errorKey != null;
}
