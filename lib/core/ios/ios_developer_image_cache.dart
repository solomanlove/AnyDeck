import 'dart:io';

/// 为自动挂载指定可写缓存，避免 GUI 从只读目录启动时写入 ./devimages。
class IosDeveloperImageCache {
  IosDeveloperImageCache({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  Future<List<String>> prepare(List<String> args) async {
    if (args.length < 2 ||
        args[0] != 'image' ||
        args[1] != 'auto' ||
        args.any((arg) => arg == '--basedir' || arg.startsWith('--basedir='))) {
      return args;
    }
    final directory = (_directory ?? _defaultDirectory()).absolute;
    await directory.create(recursive: true);
    return [...args, '--basedir=${directory.path}'];
  }

  static Directory _defaultDirectory() {
    final environment = Platform.environment;
    final userHome = environment['HOME'] ?? environment['USERPROFILE'];
    final cacheRoot = Platform.isMacOS && userHome != null
        ? '$userHome/Library/Caches'
        : Platform.isWindows
        ? environment['LOCALAPPDATA']
        : environment['XDG_CACHE_HOME'] ??
              (userHome == null ? null : '$userHome/.cache');
    return Directory(
      '${cacheRoot ?? Directory.systemTemp.path}/AnyDeck/ios/devimages',
    );
  }
}
