import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import 'remote_file.dart';

class FileManagerService {
  FileManagerService(this._adb);

  final AdbService _adb;

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

  Future<AdbResult> push(String deviceId, String localPath, String remotePath) {
    return _adb.run(['-s', deviceId, 'push', localPath, remotePath]);
  }

  Future<AdbResult> pull(String deviceId, String remotePath, String localPath) {
    return _adb.run(['-s', deviceId, 'pull', remotePath, localPath]);
  }

  Future<AdbResult> delete(String deviceId, String remotePath) {
    return _adb.shellArgs(deviceId, ['rm', '-rf', remotePath]);
  }

  Future<AdbResult> makeDirectory(String deviceId, String remotePath) {
    return _adb.shellArgs(deviceId, ['mkdir', '-p', remotePath]);
  }

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
