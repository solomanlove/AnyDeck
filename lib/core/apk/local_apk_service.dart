import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'local_apk_info.dart';

/// 运行随应用打包的解析器；每次读取新文件，退出/超时都终止进程。
class LocalApkService {
  LocalApkService({
    String? executable,
    this.timeout = const Duration(seconds: 30),
  }) : executable =
           executable ??
           '${File(Platform.resolvedExecutable).parent.parent.path}/Helpers/anydeck-apk-inspector';

  final String executable;
  final Duration timeout;
  Process? _process;
  bool _disposed = false;
  static const maxOutputBytes = 16 * 1024 * 1024;

  Future<LocalApkInfo> inspect(String path) async {
    final file = File(path);
    if (!path.toLowerCase().endsWith('.apk') || !await file.exists()) {
      throw const FormatException('apkInvalidFile');
    }
    final before = await file.stat();
    if (_disposed) throw const FormatException('apkCancelled');
    final process = await Process.start(executable, [file.absolute.path]);
    _process = process;
    if (_disposed) process.kill(ProcessSignal.sigkill);
    try {
      final result = await Future.wait<Object>([
        process.exitCode,
        _readLimited(process.stdout, maxOutputBytes, process),
        _readLimited(process.stderr, 64 * 1024, process),
      ]).timeout(timeout);
      final after = await file.stat();
      if (before.size != after.size || before.modified != after.modified) {
        throw const FormatException('apkFileChanged');
      }
      final output = jsonDecode(result[1] as String) as Map<String, dynamic>;
      if (result[0] != 0 || output['error'] != null) {
        throw FormatException(output['error']?.toString() ?? 'apkParseFailed');
      }
      output['size'] = after.size;
      output['modified'] = after.modified.microsecondsSinceEpoch;
      return LocalApkInfo(output);
    } on TimeoutException {
      throw const FormatException('apkParseTimeout');
    } finally {
      process.kill(ProcessSignal.sigkill);
      if (identical(_process, process)) _process = null;
    }
  }

  Future<String> _readLimited(
    Stream<List<int>> stream,
    int limit,
    Process process,
  ) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > limit) {
        process.kill(ProcessSignal.sigkill);
        throw const FormatException('apkOutputLimit');
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  void dispose() {
    _disposed = true;
    _process?.kill(ProcessSignal.sigkill);
  }
}
