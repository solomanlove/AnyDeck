import 'dart:async';
import 'dart:io';

/// 等待主界面就绪后串行分发文件；规范化路径使符号链接也复用同一窗口。
class ApkFileOpenQueue {
  ApkFileOpenQueue({
    required this.ready,
    required this.openDocument,
    required this.onError,
  });
  final Future<void> ready;
  final Future<void> Function(String path) openDocument;
  final void Function(Object error) onError;
  Future<void> _pending = Future<void>.value();
  Future<void> get idle => _pending;

  void add(Object? paths) {
    if (paths is! List) return;
    for (final path in paths.whereType<String>()) {
      if (!path.toLowerCase().endsWith('.apk')) continue;
      _pending = _pending
          .then((_) async {
            await ready;
            final file = File(path);
            final canonical = await file.exists()
                ? await file.resolveSymbolicLinks()
                : file.absolute.path;
            await openDocument(canonical);
          })
          .catchError(onError);
    }
  }
}
