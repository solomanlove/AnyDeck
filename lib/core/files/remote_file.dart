/// 根据 Android `ls` 解析出的文件类型。
enum RemoteFileType { folder, file, link }

/// 设备文件浏览器展示的远程文件条目。
class RemoteFile {
  const RemoteFile({
    required this.name,
    required this.type,
    this.permissions = '',
    this.modifiedDate = '',
    this.size,
    this.linkTarget,
  });

  final String name;
  final RemoteFileType type;
  final String permissions;
  final String modifiedDate;
  final int? size;
  final String? linkTarget;

  /// 目录条目可以在文件浏览器中继续打开。
  bool get isFolder => type == RemoteFileType.folder;

  /// 链接条目。
  bool get isLink => type == RemoteFileType.link;

  /// 格式化后的文件大小。
  String get formattedSize {
    if (size == null || isFolder || isLink) {
      return '--';
    }
    if (size == 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double bytes = size!.toDouble();
    while (bytes >= 1024 && i < suffixes.length - 1) {
      bytes /= 1024;
      i++;
    }
    return '${bytes.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}
