import 'dart:io';

import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import '../harmony/hdc_service.dart';
import 'remote_file.dart';

typedef DeviceHarmonyResolver = bool Function(String deviceId);

/// 基于 ADB / HDC 命令实现的远程文件浏览能力。
class FileManagerService {
  FileManagerService(
    this._adb, {
    HdcService? hdc,
    DeviceHarmonyResolver? isHarmonyResolver,
    Directory? exportTempRoot,
  }) : _hdc = hdc,
       _isHarmonyResolver = isHarmonyResolver,
       _exportTempRoot = exportTempRoot;

  static const _fileTransferTimeout = Duration(minutes: 5);
  static const _harmonyExportTimeout = Duration(minutes: 30);
  static const _fallbackHarmonyDownloadPath =
      '/storage/media/100/local/files/Docs/Download/';

  final AdbService _adb;
  final HdcService? _hdc;
  final DeviceHarmonyResolver? _isHarmonyResolver;
  final Directory? _exportTempRoot;

  bool _isHarmonyDevice(String deviceId) =>
      (_isHarmonyResolver?.call(deviceId) ?? false) && _hdc != null;

  /// 列出远程目录，并解析详细属性。
  Future<List<RemoteFile>> listFiles(String deviceId, String remotePath) async {
    // 尝试不同的 ls 选项以获取最详细的文件元数据。
    // 第一选择：ls -llA (长格式，带秒/纳秒，隐藏 . 和 ..)
    // 第二选择：ls -lA (长格式，隐藏 . 和 ..)
    // 第三选择：ls -la (长格式，显示所有文件)
    const listTimeout = Duration(seconds: 5);
    final hdc = _hdc;
    final isHarmony = _isHarmonyDevice(deviceId);

    AdbResult result;
    if (isHarmony && hdc != null) {
      final escaped = remotePath.replaceAll("'", "'\\''");
      result = await hdc.shell(
        deviceId,
        "ls -llA '$escaped'",
        timeout: listTimeout,
      );

      bool shouldFallback(AdbResult res) {
        final err = res.stderr.toLowerCase();
        return err.contains('invalid option') ||
            err.contains('unknown option') ||
            err.contains('usage: ls') ||
            err.contains('bad option');
      }

      if (shouldFallback(result)) {
        result = await hdc.shell(
          deviceId,
          "ls -lA '$escaped'",
          timeout: listTimeout,
        );
      }
      if (shouldFallback(result)) {
        result = await hdc.shell(
          deviceId,
          "ls -la '$escaped'",
          timeout: listTimeout,
        );
      }
    } else {
      result = await _adb.shellArgs(deviceId, [
        'ls',
        '-llA',
        remotePath,
      ], timeout: listTimeout);

      bool shouldFallback(AdbResult res) {
        final err = res.stderr.toLowerCase();
        return err.contains('invalid option') ||
            err.contains('unknown option') ||
            err.contains('usage: ls') ||
            err.contains('bad option');
      }

      if (shouldFallback(result)) {
        result = await _adb.shellArgs(deviceId, [
          'ls',
          '-lA',
          remotePath,
        ], timeout: listTimeout);
      }
      if (shouldFallback(result)) {
        result = await _adb.shellArgs(deviceId, [
          'ls',
          '-la',
          remotePath,
        ], timeout: listTimeout);
      }
    }

    // 即使命令返回非零（如有些 root 目录部分文件无权限导致 ls 返回 1），
    // 只要 stdout 不为空，我们就可以部分展示获取到的内容。
    if (result.stdout.trim().isEmpty && !result.isSuccess) {
      throw Exception(result.message.isNotEmpty ? result.message : '无法列出目录内容');
    }

    final files = <RemoteFile>[];
    final lines = result.stdout.split('\n');
    for (final line in lines) {
      final file = _parseLongLine(line);
      if (file != null) {
        // 过滤掉 . 和 .. 目录
        if (file.name == '.' || file.name == '..') {
          continue;
        }
        files.add(file);
      }
    }

    // 排序：文件夹排在前面，然后再按名称字母不区分大小写排序。
    return files..sort((left, right) {
      if (left.type != right.type) {
        return left.isFolder ? -1 : 1;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
  }

  /// 上传本地文件或目录到当前远程路径。
  Future<AdbResult> push(String deviceId, String localPath, String remotePath) {
    final hdc = _hdc;
    if (_isHarmonyDevice(deviceId) && hdc != null) {
      return hdc.fileSend(
        deviceId,
        localPath,
        remotePath,
        timeout: _fileTransferTimeout,
      );
    }
    return _adb.run([
      '-s',
      deviceId,
      'push',
      localPath,
      remotePath,
    ], timeout: _fileTransferTimeout);
  }

  /// 下载远程文件到本地目标路径。
  Future<AdbResult> pull(String deviceId, String remotePath, String localPath) {
    final hdc = _hdc;
    if (_isHarmonyDevice(deviceId) && hdc != null) {
      return hdc.fileRecv(
        deviceId,
        remotePath,
        localPath,
        timeout: _fileTransferTimeout,
      );
    }
    return _adb.run([
      '-s',
      deviceId,
      'pull',
      remotePath,
      localPath,
    ], timeout: _fileTransferTimeout);
  }

  /// 将鸿蒙调试目录中的文件或文件夹导出到手机文件管理的“下载”目录。
  ///
  /// HarmonyOS 安全策略会拒绝 shell 直接跨域复制，因此先拉取到桌面端临时目录，
  /// 再通过 HDC file send 写入用户文件目录；临时中转内容始终在 finally 中清理。
  Future<AdbResult> exportToHarmonyDownloads(
    String deviceId,
    String remotePath,
    String fileName,
  ) async {
    final hdc = _hdc;
    if (!_isHarmonyDevice(deviceId) || hdc == null) {
      return const AdbResult(
        exitCode: 1,
        stdout: '',
        stderr: '仅鸿蒙设备支持导出到手机文件管理',
      );
    }
    if (fileName.isEmpty ||
        fileName == '.' ||
        fileName == '..' ||
        fileName.contains('/')) {
      return const AdbResult(exitCode: 1, stdout: '', stderr: '文件名无效，无法导出');
    }

    Directory? stagingDirectory;
    try {
      final tempRoot = _exportTempRoot ?? Directory.systemTemp;
      if (!await tempRoot.exists()) {
        await tempRoot.create(recursive: true);
      }
      stagingDirectory = await tempRoot.createTemp('anydeck_harmony_export_');

      final receiveResult = await hdc.fileRecv(
        deviceId,
        remotePath,
        stagingDirectory.path,
        timeout: _harmonyExportTimeout,
      );
      if (!receiveResult.isSuccess) {
        return receiveResult;
      }

      final localPath = '${stagingDirectory.path}/$fileName';
      if (await FileSystemEntity.type(localPath) ==
          FileSystemEntityType.notFound) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: 'HDC 未生成本地中转文件',
        );
      }

      final downloadPath = await _resolveHarmonyDownloadPath(deviceId, hdc);
      return await hdc.fileSend(
        deviceId,
        localPath,
        downloadPath,
        timeout: _harmonyExportTimeout,
      );
    } on FileSystemException catch (error) {
      return AdbResult(
        exitCode: 1,
        stdout: '',
        stderr: '创建或清理本地中转文件失败: ${error.message}',
      );
    } finally {
      final directory = stagingDirectory;
      if (directory != null && await directory.exists()) {
        try {
          await directory.delete(recursive: true);
        } on FileSystemException {
          // 中转清理失败不覆盖已经返回的 HDC 传输结果。
        }
      }
    }
  }

  Future<String> _resolveHarmonyDownloadPath(
    String deviceId,
    HdcService hdc,
  ) async {
    final mountResult = await hdc.shell(
      deviceId,
      'mount',
      timeout: const Duration(seconds: 5),
    );
    if (mountResult.isSuccess) {
      final match = RegExp(
        r'(/storage/media/\d+/local/files/Docs)\s+on\s+',
      ).firstMatch(mountResult.stdout);
      if (match != null) {
        return '${match.group(1)}/Download/';
      }
    }
    return _fallbackHarmonyDownloadPath;
  }

  /// 启动由上层管理生命周期的下载进程，用于支持预览取消。
  Future<Process> startPull(
    String deviceId,
    String remotePath,
    String localPath,
  ) {
    final hdc = _hdc;
    if (_isHarmonyDevice(deviceId) && hdc != null) {
      return hdc.startFileRecv(deviceId, remotePath, localPath);
    }
    return _adb.start(['-s', deviceId, 'pull', remotePath, localPath]);
  }

  /// 递归删除远程文件路径。
  Future<AdbResult> delete(String deviceId, String remotePath) {
    final hdc = _hdc;
    if (_isHarmonyDevice(deviceId) && hdc != null) {
      return hdc.delete(deviceId, remotePath);
    }
    return _adb.shellArgs(deviceId, ['rm', '-rf', remotePath]);
  }

  /// 创建远程目录及缺失的父目录。
  Future<AdbResult> makeDirectory(String deviceId, String remotePath) {
    final hdc = _hdc;
    if (_isHarmonyDevice(deviceId) && hdc != null) {
      return hdc.makeDirectory(deviceId, remotePath);
    }
    return _adb.shellArgs(deviceId, ['mkdir', '-p', remotePath]);
  }

  /// 解析单行 `ls -l` 输出。
  RemoteFile? _parseLongLine(String line) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('total ') || line.startsWith('ls: ')) {
      return null;
    }

    final tokens = line.split(RegExp(r'\s+'));
    if (tokens.length < 8) {
      return null;
    }

    final permissions = tokens[0];
    if (permissions.length != 10) {
      return null;
    }

    final typeChar = permissions[0];
    RemoteFileType type;
    if (typeChar == 'd') {
      type = RemoteFileType.folder;
    } else if (typeChar == 'l') {
      type = RemoteFileType.link;
    } else {
      type = RemoteFileType.file;
    }

    final sizeStr = tokens[4];
    final int? size = int.tryParse(sizeStr);

    int nameTokenIndex = 7;
    String dateStr = '';

    if (tokens[5].contains('-')) {
      // ISO date format (YYYY-MM-DD)
      final timeToken = tokens[6];
      // 检查 token 7 是否为时区 (如 +0800)
      if (tokens.length > 7 &&
          (tokens[7].startsWith('+') || tokens[7].startsWith('-')) &&
          RegExp(r'^\d+$').hasMatch(tokens[7].substring(1))) {
        dateStr = '${tokens[5]} $timeToken';
        nameTokenIndex = 8;
      } else {
        dateStr = '${tokens[5]} $timeToken';
        nameTokenIndex = 7;
      }
    } else {
      // 非 ISO 日期格式 (Month Day Time/Year)
      dateStr = '${tokens[5]} ${tokens[6]} ${tokens[7]}';
      nameTokenIndex = 8;
    }

    // 通过顺序扫描原始行来精确定位文件名的起始索引，以完美保留连续空格
    var currentIndex = 0;
    for (var i = 0; i < nameTokenIndex; i++) {
      final token = tokens[i];
      final tokenPos = line.indexOf(token, currentIndex);
      if (tokenPos == -1) {
        return null;
      }
      currentIndex = tokenPos + token.length;
    }
    final fullName = line.substring(currentIndex).trimLeft();

    String name = fullName;
    String? linkTarget;
    if (type == RemoteFileType.link && fullName.contains(' -> ')) {
      final parts = fullName.split(' -> ');
      name = parts[0];
      linkTarget = parts[1];
    }

    // 清理带纳秒的时间，仅保留到秒
    if (dateStr.contains('.')) {
      final dotIndex = dateStr.indexOf('.');
      dateStr = dateStr.substring(0, dotIndex);
    }

    return RemoteFile(
      name: name,
      type: type,
      permissions: permissions,
      modifiedDate: dateStr,
      size: size,
      linkTarget: linkTarget,
    );
  }
}
