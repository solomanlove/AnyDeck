import 'dart:io';

import 'package:any_deck/core/nearby_share/share_record_file_actions.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:any_deck/core/process/host_platform_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends Fake implements HostPlatformService {
  String? file;
  String? directory;
  @override
  Future<bool> openFile(String path) async {
    file = path;
    return true;
  }

  @override
  Future<bool> openDirectory(String path) async {
    directory = path;
    return true;
  }
}

void main() {
  test('路径操作按用户点击执行；文件丢失不启动程序，仍可打开所在目录', () async {
    final root = await Directory.systemTemp.createTemp(
      'anydeck-record-action-test-',
    );
    try {
      final file = await File(
        '${root.path}/synthetic;not-a-command.bin',
      ).writeAsBytes([1]);
      final record = ShareTransferRecord(
        id: '1',
        direction: ShareTransferDirection.receive,
        status: ShareTransferStatus.succeeded,
        deviceName: 'nova',
        address: '192.168.1.3',
        fileName: 'synthetic.bin',
        path: file.path,
        bytes: 1,
        createdAt: DateTime(2026),
      );
      final host = _Host();
      final actions = ShareRecordFileActions(host: host);
      expect(await actions.open(record), isTrue);
      expect(host.file, file.absolute.path);
      await file.delete();
      host.file = null;
      expect(await actions.open(record), isFalse);
      expect(host.file, isNull);
      expect(await actions.open(record, folder: true), isTrue);
      expect(host.directory, root.absolute.path);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
