import 'dart:io';

import '../process/host_platform_service.dart';
import 'share_transfer_record.dart';

/// 复用宿主文件操作；只在用户点击后打开，历史查询本身不读取文件内容或启动程序。
class ShareRecordFileActions {
  ShareRecordFileActions({HostPlatformService? host})
    : _host = host ?? HostPlatformService();
  final HostPlatformService _host;
  Future<bool> open(ShareTransferRecord record, {bool folder = false}) async {
    try {
      final path = record.path;
      if (path == null || path.isEmpty) return false;
      final file = File(path).absolute;
      if (folder) {
        if (!await file.parent.exists()) return false;
        return await _host
            .openDirectory(file.parent.path)
            .timeout(const Duration(seconds: 15), onTimeout: () => false);
      }
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return false;
      }
      return await _host
          .openFile(file.path)
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }
}
