/// 本地 Android 包格式；APKS/AAB/XAPK 当前仅提供离线分析。
enum AndroidPackageFormat {
  apk,
  apks,
  aab,
  xapk;

  String get label => name.toUpperCase();

  static AndroidPackageFormat? fromPath(String path) {
    final filename = path.split(RegExp(r'[/\\]')).last;
    final dot = filename.lastIndexOf('.');
    if (dot < 0) return null;
    final extension = filename.substring(dot + 1).toLowerCase();
    return values.where((format) => format.name == extension).firstOrNull;
  }
}
