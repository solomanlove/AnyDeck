/// 将文本流按行读取，并限制单行长度，避免损坏日志撑大内存缓冲区。
Stream<String> readBoundedLogcatLines(
  Stream<String> chunks, {
  int maxLineLength = 16384,
}) async* {
  assert(maxLineLength > 0);
  var pending = '';
  await for (final chunk in chunks) {
    var start = 0;
    while (start < chunk.length) {
      final end = chunk.indexOf('\n', start);
      final segmentEnd = end < 0 ? chunk.length : end;
      final remaining = maxLineLength - pending.length;
      if (remaining > 0) {
        final take = (segmentEnd - start).clamp(0, remaining);
        pending += chunk.substring(start, start + take);
      }
      if (end < 0) break;
      yield pending.endsWith('\r')
          ? pending.substring(0, pending.length - 1)
          : pending;
      pending = '';
      start = end + 1;
    }
  }
  if (pending.isNotEmpty) yield pending;
}
