import 'dart:async';

import '../logging/app_log_recorder.dart';

/// 持续排空Core stderr，仅记录固定格式的失败类别；不落盘路径、文件内容或原始报文。
StreamSubscription<List<int>> drainShareCoreErrors(Stream<List<int>> source) {
  final pending = <int>[];
  var oversized = false;
  final category = RegExp(r'^Honor (send|receive) failed: ([a-z_]{1,64})\r?$');
  void finishLine() {
    if (!oversized) {
      final match = category.firstMatch(String.fromCharCodes(pending));
      if (match != null) {
        AppLogRecorder.instance.record(
          'operation=${match[1]} reason=${match[2]}',
          tag: 'share_core',
          level: 'E',
        );
      }
    }
    pending.clear();
    oversized = false;
  }

  return source.listen((bytes) {
    for (final byte in bytes) {
      if (byte == 10) {
        finishLine();
      } else if (!oversized) {
        if (pending.length < 256) {
          pending.add(byte);
        } else {
          pending.clear();
          oversized = true;
        }
      }
    }
  }, onDone: finishLine);
}
