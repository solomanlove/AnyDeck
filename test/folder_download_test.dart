import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/files/file_manager_service.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAdbService extends AdbService {
  _RecordingAdbService() : super(executable: 'adb');

  List<String>? lastArgs;

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    lastArgs = args;
    return const AdbResult(
      exitCode: 0,
      stdout: '1 file pulled',
      stderr: '',
    );
  }
}

class _RecordingHdcService extends HdcService {
  _RecordingHdcService() : super(executable: 'hdc');

  String? lastDeviceId;
  String? lastRemotePath;
  String? lastLocalPath;

  @override
  Future<AdbResult> fileRecv(
    String deviceId,
    String remotePath,
    String localPath, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    lastDeviceId = deviceId;
    lastRemotePath = remotePath;
    lastLocalPath = localPath;
    return const AdbResult(
      exitCode: 0,
      stdout: 'FileTransfer finish',
      stderr: '',
    );
  }
}

void main() {
  group('文件夹与文件下载测试', () {
    test('ADB 模式下载单个文件夹到指定目录', () async {
      final adb = _RecordingAdbService();
      final service = FileManagerService(adb);

      const deviceId = 'device_001';
      const remoteFolderPath = '/storage/emulated/0/DCIM/Camera';
      const targetDirectory = '/Users/test/Downloads';

      // 当目标为文件夹时，直接下载到用户指定的目录中
      final result = await service.pull(
        deviceId,
        remoteFolderPath,
        targetDirectory,
      );

      expect(result.isSuccess, isTrue);
      expect(adb.lastArgs, [
        '-s',
        deviceId,
        'pull',
        remoteFolderPath,
        targetDirectory,
      ]);
    });

    test('HDC 模式下载单个文件夹到指定目录', () async {
      final adb = _RecordingAdbService();
      final hdc = _RecordingHdcService();
      final service = FileManagerService(
        adb,
        hdc: hdc,
        isHarmonyResolver: (id) => id.startsWith('harmony_'),
      );

      const deviceId = 'harmony_001';
      const remoteFolderPath = '/data/storage/el2/base/files/folder1';
      const targetDirectory = '/Users/test/Downloads';

      final result = await service.pull(
        deviceId,
        remoteFolderPath,
        targetDirectory,
      );

      expect(result.isSuccess, isTrue);
      expect(hdc.lastDeviceId, deviceId);
      expect(hdc.lastRemotePath, remoteFolderPath);
      expect(hdc.lastLocalPath, targetDirectory);
    });
  });
}
