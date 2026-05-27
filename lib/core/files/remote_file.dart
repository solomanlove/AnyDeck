/// 根据 Android `ls -F` 后缀推断出的文件类型。
enum RemoteFileType { folder, file, link }

/// 设备文件浏览器展示的远程文件条目。
class RemoteFile {
  const RemoteFile({required this.name, required this.type});

  final String name;
  final RemoteFileType type;

  /// 目录条目可以在文件浏览器中继续打开。
  bool get isFolder => type == RemoteFileType.folder;
}
