import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 等待 HarmonyOS 投屏 sidecar 输出就绪端口，并保留真实启动失败原因。
class HarmonySidecarStartup {
  const HarmonySidecarStartup._();

  static Future<int> waitForPort({
    required Stream<List<int>> stdoutStream,
    required Stream<List<int>> stderrStream,
    required Future<int> exitCode,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final completer = Completer<int>();
    final stderrLines = <String>[];

    final stdoutSubscription = stdoutStream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stdout.writeln('[hoscrcpy-sidecar stdout] $line');
          if (completer.isCompleted) return;
          try {
            final data = jsonDecode(line.trim());
            if (data is! Map<String, dynamic> || data['ready'] != true) return;
            final port = data['port'];
            if (port is int && port > 0 && port <= 65535) {
              completer.complete(port);
            }
          } catch (_) {
            // sidecar 依赖可能输出普通诊断日志，只消费合法的 ready JSON。
          }
        });

    final stderrSubscription = stderrStream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderr.writeln('[hoscrcpy-sidecar stderr] $line');
          if (stderrLines.length == 8) stderrLines.removeAt(0);
          stderrLines.add(line.trim());
        });

    unawaited(
      exitCode.then((code) {
        if (completer.isCompleted) return;
        final detail = stderrLines.where((line) => line.isNotEmpty).join(' | ');
        completer.completeError(
          Exception(
            detail.isEmpty
                ? 'HarmonyOS mirror sidecar exited before ready (code $code)'
                : 'HarmonyOS mirror sidecar exited before ready (code $code): $detail',
          ),
        );
      }),
    );

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          final detail = stderrLines
              .where((line) => line.isNotEmpty)
              .join(' | ');
          throw TimeoutException(
            detail.isEmpty
                ? 'HarmonyOS mirror sidecar did not report a port'
                : 'HarmonyOS mirror sidecar did not report a port: $detail',
            timeout,
          );
        },
      );
    } catch (_) {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      rethrow;
    }
  }
}
