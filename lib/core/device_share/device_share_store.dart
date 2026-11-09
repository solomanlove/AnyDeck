import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'device_share_models.dart';

/// 主窗口独占的共享规则/历史存储；测试可使用纯内存实现。
abstract class DeviceShareStore {
  Future<DeviceShareSavedState> load();
  Future<void> save(DeviceShareSavedState value);
}

class MemoryDeviceShareStore implements DeviceShareStore {
  DeviceShareSavedState value = const DeviceShareSavedState();
  @override
  Future<DeviceShareSavedState> load() async => value;
  @override
  Future<void> save(DeviceShareSavedState value) async => this.value = value;
}

/// 私有目录 0700、凭据文件 0600，先限制权限再写入内容，原子替换并串行落盘。
/// 不把分享码、TLS 私钥或 Wi-Fi 规则写入 SharedPreferences 和诊断日志。
class FileDeviceShareStore implements DeviceShareStore {
  FileDeviceShareStore({this.directory});
  final Directory? directory;
  Future<void> _tail = Future.value();

  Future<Directory> _directory() async =>
      directory ??
      Directory(
        '${(await getApplicationSupportDirectory()).path}/device-sharing',
      );

  @override
  Future<DeviceShareSavedState> load() async {
    await _tail;
    final file = File('${(await _directory()).path}/state.json');
    if (!await file.exists()) return const DeviceShareSavedState();
    return DeviceShareSavedState.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> save(DeviceShareSavedState value) {
    final encoded = jsonEncode(value.toJson());
    final operation = _tail.then((_) async {
      final root = await _directory();
      await root.create(recursive: true);
      await _permissions(root.path, '700');
      final temporary = File('${root.path}/state.pending');
      try {
        await temporary.create();
        await _permissions(temporary.path, '600');
        await temporary.writeAsString(encoded, flush: true);
        await temporary.rename('${root.path}/state.json');
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
    _tail = operation.catchError((Object error, StackTrace stack) {});
    return operation;
  }

  Future<void> _permissions(String path, String mode) async {
    if (Platform.isWindows) return; // AppData 目录沿用当前用户的 ACL。
    final process = await Process.start('/bin/chmod', [mode, path]);
    final output = process.stdout.drain<void>();
    final errors = process.stderr.drain<void>();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      rethrow;
    } finally {
      await Future.wait([output, errors]);
    }
    if (exitCode != 0) {
      throw const FileSystemException('Share store access');
    }
  }
}
