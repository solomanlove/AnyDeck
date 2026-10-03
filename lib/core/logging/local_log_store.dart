import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 每个 Isolate 独占日志文件，串行写入并轮转，避免多窗口竞争同一文件。
class LocalLogStore {
  LocalLogStore(this.directory, this.source, {this.maxBytes = 2 * 1024 * 1024});

  final Directory directory;
  final String source;
  final int maxBytes;
  final List<String> _pending = [];
  Future<void>? _writing;
  Timer? _timer;
  String? lastError;
  int _dropped = 0;

  /// 写入失败或缓冲溢出造成的缺失数量，用于标记不完整报告。
  int lostRecords = 0;

  File get _current => File('${directory.path}/anydeck_$source.log');
  File get _previous => File('${directory.path}/anydeck_$source.previous.log');

  /// 有界缓冲防止磁盘缓慢时无限积压；错误日志由调用方立即 flush。
  void add(String line) {
    if (_pending.length >= 256) {
      _pending.removeAt(0);
      _dropped++;
      lostRecords++;
    }
    _pending.add(line);
    _timer ??= Timer(const Duration(milliseconds: 500), () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final writing = _writing;
    if (writing != null) {
      await writing;
      if (_pending.isNotEmpty) await flush();
      return;
    }
    if (_pending.isEmpty) return;
    final batch = List<String>.from(_pending);
    _pending.clear();
    if (_dropped > 0) {
      batch.insert(0, '[logging] Dropped $_dropped records: disk queue full.');
      _dropped = 0;
    }
    final task = _append(batch);
    _writing = task;
    await task;
    _writing = null;
  }

  Future<void> _append(List<String> batch) async {
    try {
      await directory.create(recursive: true);
      var length = await _current.exists() ? await _current.length() : 0;
      // 每批分块写入，避免每条日志都触发打开文件和磁盘 flush。
      var chunk = <int>[];
      for (final line in batch) {
        final bytes = utf8.encode('$line\n');
        if (length + chunk.length + bytes.length > maxBytes) {
          if (chunk.isNotEmpty) {
            await _current.writeAsBytes(
              chunk,
              mode: FileMode.append,
              flush: true,
            );
            chunk = [];
          }
          if (await _previous.exists()) await _previous.delete();
          if (await _current.exists()) await _current.rename(_previous.path);
          length = 0;
        }
        chunk.addAll(bytes);
      }
      if (chunk.isNotEmpty) {
        await _current.writeAsBytes(chunk, mode: FileMode.append, flush: true);
      }
      lastError = null;
    } catch (error) {
      // 日志 IO 失败不能再次写日志，否则会递归放大故障。
      lastError = error.toString();
      lostRecords += batch.length;
    }
  }

  /// 只管理自有日志，按修改时间保留最近文件；主窗口启动时调用。
  Future<void> prune({int keep = 40}) async {
    final files = await filesNewestFirst();
    for (final file in files.skip(keep)) {
      // 活跃进程的多窗口文件由各自轮转，不能在启动时删除。
      if (file.uri.pathSegments.last.startsWith('anydeck_${pid}_')) continue;
      try {
        await file.delete();
      } on FileSystemException {
        // 并发导出或清理时文件可能已消失。
      }
    }
  }

  Future<List<File>> filesNewestFirst() async {
    if (!await directory.exists()) return [];
    final files = <(File, DateTime)>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !entity.uri.pathSegments.last.startsWith('anydeck_') ||
          !entity.path.endsWith('.log')) {
        continue;
      }
      final stat = await entity.stat();
      files.add((entity, stat.modified));
    }
    files.sort((a, b) => b.$2.compareTo(a.$2));
    return files.map((entry) => entry.$1).toList();
  }
}
