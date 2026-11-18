import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 执行短时工具探测，限制输出，并在超时后终止进程和回收管道。
///
/// [arguments] 直接传给进程，禁止 Shell 拼接；返回的 stdout/stderr 为 UTF-8 文本。
Future<ProcessResult> runBoundedProcess(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 4),
  int maxOutputBytes = 64 * 1024,
}) async {
  final process = await Process.start(executable, arguments, runInShell: false);
  final out = <int>[];
  final err = <int>[];
  void append(List<int> target, List<int> bytes) {
    final remaining = maxOutputBytes - target.length;
    if (remaining > 0) target.addAll(bytes.take(remaining));
  }

  final stdout = process.stdout.listen((bytes) => append(out, bytes));
  final stderr = process.stderr.listen((bytes) => append(err, bytes));
  final outputDone = Future.wait([
    stdout.asFuture<void>(),
    stderr.asFuture<void>(),
  ]);
  try {
    // CLI 可能在关闭输入前已经退出，关闭失败也必须走同一资源回收路径。
    await process.stdin.close().timeout(timeout);
    final code = await process.exitCode.timeout(timeout);
    // exitCode 完成后让已经入队的管道事件完成，再生成快照。
    await outputDone.timeout(timeout);
    return ProcessResult(
      process.pid,
      code,
      utf8.decode(out, allowMalformed: true),
      utf8.decode(err, allowMalformed: true),
    );
  } catch (_) {
    process.kill();
    await process.exitCode.timeout(
      const Duration(milliseconds: 500),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    rethrow;
  } finally {
    await stdout.cancel();
    await stderr.cancel();
  }
}
