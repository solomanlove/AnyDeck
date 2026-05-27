import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import 'remote_file.dart';

/// 基于 adb push/pull/shell 命令实现的远程文件浏览能力。
class FileManagerService {
  FileManagerService(this._adb);

  final AdbService _adb;

  /// 列出远程目录，并将目录排在文件前面，方便导航。
  Future<List<RemoteFile>> listFiles(String deviceId, String remotePath) async {
    final result = await _adb.shellArgs(deviceId, ['ls', '-1FA', remotePath]);
    if (!result.isSuccess) {
      throw Exception(result.message);
    }
    final files = result.stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(_parseLine)
        .toList(growable: false);
    return files..sort((left, right) {
      if (left.type != right.type) {
        return left.isFolder ? -1 : 1;
      }
      return left.name.compareTo(right.name);
    });
  }

  /// 上传本地文件或目录到当前远程路径。
  Future<AdbResult> push(String deviceId, String localPath, String remotePath) {
    return _adb.run(['-s', deviceId, 'push', localPath, remotePath]);
  }

  /// 下载远程文件到本地目标路径。
  Future<AdbResult> pull(String deviceId, String remotePath, String localPath) {
    return _adb.run(['-s', deviceId, 'pull', remotePath, localPath]);
  }

  /// 递归删除远程文件路径。
  Future<AdbResult> delete(String deviceId, String remotePath) {
    return _adb.shellArgs(deviceId, ['rm', '-rf', remotePath]);
  }

  /// 创建远程目录及缺失的父目录。
  Future<AdbResult> makeDirectory(String deviceId, String remotePath) {
    return _adb.shellArgs(deviceId, ['mkdir', '-p', remotePath]);
  }

  /// 将 `ls -F` 后缀转换为带类型的文件条目。
  RemoteFile _parseLine(String line) {
    if (line.endsWith('/')) {
      return RemoteFile(
        name: line.substring(0, line.length - 1),
        type: RemoteFileType.folder,
      );
    }
    if (line.endsWith('@')) {
      return RemoteFile(
        name: line.substring(0, line.length - 1),
        type: RemoteFileType.link,
      );
    }
    if (line.endsWith('*')) {
      return RemoteFile(
        name: line.substring(0, line.length - 1),
        type: RemoteFileType.file,
      );
    }
    return RemoteFile(name: line, type: RemoteFileType.file);
  }
}
