import 'dart:io';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/files/file_manager_service.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestAdbService extends AdbService {
  _TestAdbService() : super(executable: 'adb');
}

class _ExportHdcService extends HdcService {
  _ExportHdcService({required this.receiveDirectory})
    : super(executable: 'hdc');

  final bool receiveDirectory;
  String? sentRemotePath;
  FileSystemEntityType? sentEntityType;
  String? sentFileContents;

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return const AdbResult(
      exitCode: 0,
      stdout:
          '/storage/media/123/local/files/Docs on '
          '/mnt/user/123/currentUser/other type sharefs',
      stderr: '',
    );
  }

  @override
  Future<AdbResult> fileRecv(
    String deviceId,
    String remotePath,
    String localPath, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final name = remotePath.split('/').last;
    if (receiveDirectory) {
      final directory = Directory('$localPath/$name');
      await directory.create();
      await File('${directory.path}/child.txt').writeAsString('folder data');
    } else {
      await File('$localPath/$name').writeAsString('file data');
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<AdbResult> fileSend(
    String deviceId,
    String localPath,
    String remotePath, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    sentRemotePath = remotePath;
    sentEntityType = await FileSystemEntity.type(localPath);
    if (sentEntityType == FileSystemEntityType.file) {
      sentFileContents = await File(localPath).readAsString();
    } else if (sentEntityType == FileSystemEntityType.directory) {
      sentFileContents = await File('$localPath/child.txt').readAsString();
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  const deviceId = 'harmony-device';

  test('stages a HarmonyOS file and sends it to phone Downloads', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'anydeck_export_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    });
    final hdc = _ExportHdcService(receiveDirectory: false);
    final service = FileManagerService(
      _TestAdbService(),
      hdc: hdc,
      isHarmonyResolver: (_) => true,
      exportTempRoot: tempRoot,
    );

    final result = await service.exportToHarmonyDownloads(
      deviceId,
      '/data/local/tmp/test.txt',
      'test.txt',
    );

    expect(result.isSuccess, isTrue);
    expect(hdc.sentEntityType, FileSystemEntityType.file);
    expect(hdc.sentFileContents, 'file data');
    expect(hdc.sentRemotePath, '/storage/media/123/local/files/Docs/Download/');
    expect(await tempRoot.list().toList(), isEmpty);
  });

  test('preserves a HarmonyOS directory during export', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'anydeck_export_folder_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    });
    final hdc = _ExportHdcService(receiveDirectory: true);
    final service = FileManagerService(
      _TestAdbService(),
      hdc: hdc,
      isHarmonyResolver: (_) => true,
      exportTempRoot: tempRoot,
    );

    final result = await service.exportToHarmonyDownloads(
      deviceId,
      '/data/local/tmp/test-folder',
      'test-folder',
    );

    expect(result.isSuccess, isTrue);
    expect(hdc.sentEntityType, FileSystemEntityType.directory);
    expect(hdc.sentFileContents, 'folder data');
    expect(await tempRoot.list().toList(), isEmpty);
  });
}
