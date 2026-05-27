enum RemoteFileType { folder, file, link }

class RemoteFile {
  const RemoteFile({required this.name, required this.type});

  final String name;
  final RemoteFileType type;

  bool get isFolder => type == RemoteFileType.folder;
}
