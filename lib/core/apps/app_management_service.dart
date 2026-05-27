import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import 'adb_package.dart';

class AppManagementService {
  AppManagementService(this._adb);

  final AdbService _adb;

  Future<List<AdbPackage>> listPackages(String deviceId) async {
    final result = await _adb.shellArgs(deviceId, ['pm', 'list', 'packages']);
    if (!result.isSuccess) {
      throw Exception(result.message);
    }
    final packages = result.stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('package:'))
        .map((line) => AdbPackage(line.substring('package:'.length)))
        .toList(growable: false);
    return packages..sort((left, right) => left.name.compareTo(right.name));
  }

  Future<AdbResult> installApk(String deviceId, String apkPath) {
    return _adb.run(['-s', deviceId, 'install', '-r', apkPath]);
  }

  Future<AdbResult> uninstall(String deviceId, String packageName) {
    return _adb.run(['-s', deviceId, 'uninstall', packageName]);
  }

  Future<AdbResult> launch(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['monkey', '-p', packageName, '1']);
  }

  Future<AdbResult> forceStop(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['am', 'force-stop', packageName]);
  }

  Future<AdbResult> clearData(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['pm', 'clear', packageName]);
  }

  Future<AdbResult> packagePath(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['pm', 'path', packageName]);
  }
}
