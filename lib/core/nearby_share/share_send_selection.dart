import 'dart:io';

import 'share_core_contract.dart';

/// 待发送文件的元数据快照；确认与队列只读取 stat，不读取用户文件内容。
class ShareSendFile {
  const ShareSendFile({
    required this.file,
    required this.bytes,
    required this.modified,
  });
  final File file;
  final int bytes;
  final DateTime modified;
  String get name => file.uri.pathSegments.last;

  /// 排队期间文件可能被替换，开始传输前重新校验；核心仍负责实际发送快照。
  Future<void> verifyUnchanged() async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    final stat = await file.stat();
    if (type != FileSystemEntityType.file ||
        stat.size != bytes ||
        stat.modified != modified) {
      throw const FileSystemException('Queued file changed or unavailable');
    }
  }
}

/// 一个有限大小的文件选择；去重路径并在发送任何文件前校验整个选择。
class ShareSendSelection {
  ShareSendSelection(List<ShareSendFile> files)
    : files = List.unmodifiable(files) {
    if (files.isEmpty ||
        files.length > maxFiles ||
        files.any(
          (file) =>
              file.bytes < 1 || file.bytes > ShareCoreContract.maxFileBytes,
        )) {
      throw const FormatException('Invalid file selection');
    }
    ShareCoreContract.sumFileBytes(files.map((file) => file.bytes));
  }
  static const maxFiles = 100;
  final List<ShareSendFile> files;
  int get bytes => ShareCoreContract.sumFileBytes(files.map((file) => file.bytes));

  static Future<ShareSendSelection> inspect(List<File> files) async {
    if (files.isEmpty || files.length > maxFiles) {
      throw const FormatException('Select 1 to 100 files');
    }
    final seen = <String>{};
    final selected = <ShareSendFile>[];
    for (final file in files) {
      final path = file.absolute.uri.normalizePath().toFilePath();
      if (!seen.add(path)) continue;
      final normalized = File(path);
      final type = await FileSystemEntity.type(path, followLinks: false);
      final stat = await normalized.stat();
      if (type != FileSystemEntityType.file ||
          stat.size < 1 ||
          stat.size > ShareCoreContract.maxFileBytes) {
        throw const FormatException('Only nonempty regular files');
      }
      selected.add(
        ShareSendFile(
          file: normalized,
          bytes: stat.size,
          modified: stat.modified,
        ),
      );
    }
    return ShareSendSelection(selected);
  }
}
