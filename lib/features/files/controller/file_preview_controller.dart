import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/remote_file.dart';
import '../../../core/providers/app_providers.dart';

enum FilePreviewResultType { opened, canceled, transferFailed, openFailed }

class FilePreviewResult {
  const FilePreviewResult(this.type, {this.message = ''});

  final FilePreviewResultType type;
  final String message;
}

/// Files Tab 的预览加载状态，仅保存 UI 必需信息。
class FilePreviewState {
  const FilePreviewState({this.isLoading = false, this.fileName = ''});

  final bool isLoading;
  final String fileName;
}

/// 通过 ADB pull 下载预览文件，并交给宿主机默认应用打开。
class FilePreviewController extends Notifier<FilePreviewState> {
  static const _pullTimeout = Duration(minutes: 5);
  static const _maxCachedFiles = 20;

  final LinkedHashMap<String, String> _cache = LinkedHashMap();
  Process? _activeProcess;
  File? _partialFile;
  int _generation = 0;

  @override
  FilePreviewState build() {
    ref.onDispose(_dispose);
    return const FilePreviewState();
  }

  /// 预览缓存同时包含 deviceId、远程路径和文件元数据，避免跨设备或文件更新后误用旧文件。
  Future<FilePreviewResult> preview({
    required String deviceId,
    required String remotePath,
    required RemoteFile file,
  }) async {
    cancel();
    final operation = _generation;
    state = FilePreviewState(isLoading: true, fileName: file.name);

    final cacheKey = _cacheKey(deviceId, remotePath, file);
    final cachedPath = _cache.remove(cacheKey);
    if (cachedPath != null && File(cachedPath).existsSync()) {
      _cache[cacheKey] = cachedPath;
      final result = await _openLocalFile(operation, cachedPath);
      if (operation == _generation) {
        state = const FilePreviewState();
      }
      return result;
    }

    final localFile = _previewFile(cacheKey, file.name);
    _partialFile = localFile;
    try {
      await localFile.parent.create(recursive: true);
      if (await localFile.exists()) {
        await localFile.delete();
      }

      final process = await ref
          .read(fileManagerServiceProvider)
          .startPull(deviceId, remotePath, localFile.path);
      if (operation != _generation) {
        process.kill(ProcessSignal.sigkill);
        return const FilePreviewResult(FilePreviewResultType.canceled);
      }
      _activeProcess = process;

      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      var timedOut = false;
      final exitCode = await process.exitCode.timeout(
        _pullTimeout,
        onTimeout: () async {
          timedOut = true;
          process.kill();
          return process.exitCode.timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              return 124;
            },
          );
        },
      );
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;

      if (operation != _generation) {
        await _deleteIfExists(localFile);
        return const FilePreviewResult(FilePreviewResultType.canceled);
      }
      if (timedOut || exitCode != 0 || !await localFile.exists()) {
        await _deleteIfExists(localFile);
        final message = timedOut
            ? 'timeout'
            : (stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim());
        return FilePreviewResult(
          FilePreviewResultType.transferFailed,
          message: message,
        );
      }

      _partialFile = null;
      _rememberCache(cacheKey, localFile.path);
      return _openLocalFile(operation, localFile.path);
    } on ProcessException catch (error) {
      await _deleteIfExists(localFile);
      return FilePreviewResult(
        FilePreviewResultType.transferFailed,
        message: error.message,
      );
    } on FileSystemException catch (error) {
      await _deleteIfExists(localFile);
      return FilePreviewResult(
        FilePreviewResultType.transferFailed,
        message: error.message,
      );
    } finally {
      if (operation == _generation) {
        _activeProcess = null;
        _partialFile = null;
        state = const FilePreviewState();
      }
    }
  }

  /// 取消当前预览并立即终止 ADB pull，残缺缓存不会被保留。
  void cancel() {
    _generation += 1;
    _activeProcess?.kill(ProcessSignal.sigkill);
    _activeProcess = null;
    final partialFile = _partialFile;
    _partialFile = null;
    if (partialFile != null) {
      unawaited(_deleteIfExists(partialFile));
    }
    state = const FilePreviewState();
  }

  static bool isPreviewable(RemoteFile file) {
    if (file.isFolder) return false;
    final dotIndex = file.name.lastIndexOf('.');
    if (dotIndex < 0) return false;
    return _previewableExtensions.contains(
      file.name.substring(dotIndex + 1).toLowerCase(),
    );
  }

  Future<FilePreviewResult> _openLocalFile(
    int operation,
    String localPath,
  ) async {
    final opened = await ref
        .read(hostPlatformServiceProvider)
        .openFile(localPath);
    if (operation != _generation) {
      return const FilePreviewResult(FilePreviewResultType.canceled);
    }
    return FilePreviewResult(
      opened ? FilePreviewResultType.opened : FilePreviewResultType.openFailed,
    );
  }

  File _previewFile(String cacheKey, String fileName) {
    var safeName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    safeName = safeName.replaceAll(RegExp(r'[. ]+$'), '_');
    if (safeName.isEmpty) safeName = 'preview_file';
    final hash = cacheKey.hashCode.toUnsigned(32).toRadixString(16);
    return File(
      '${Directory.systemTemp.path}/AnyDeck/previews/${hash}_$safeName',
    );
  }

  String _cacheKey(String deviceId, String remotePath, RemoteFile file) {
    return '$deviceId\n$remotePath\n${file.size ?? -1}\n${file.modifiedDate}';
  }

  void _rememberCache(String key, String path) {
    _cache[key] = path;
    while (_cache.length > _maxCachedFiles) {
      final oldestKey = _cache.keys.first;
      final oldestPath = _cache.remove(oldestKey);
      if (oldestPath != null) {
        unawaited(_deleteIfExists(File(oldestPath)));
      }
    }
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 文件可能已被另一个取消或缓存清理操作删除，无需继续抛错。
    }
  }

  void _dispose() {
    _activeProcess?.kill(ProcessSignal.sigkill);
    _activeProcess = null;
  }
}

final filePreviewControllerProvider =
    NotifierProvider<FilePreviewController, FilePreviewState>(
      FilePreviewController.new,
    );

const _previewableExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'heic',
  'heif',
  'webp',
  'bmp',
  'tiff',
  'svg',
  'ico',
  'mp4',
  'mov',
  'avi',
  'mkv',
  'm4v',
  'webm',
  '3gp',
  'mp3',
  'm4a',
  'wav',
  'flac',
  'aac',
  'ogg',
  'opus',
  'pdf',
  'txt',
  'rtf',
  'html',
  'htm',
  'md',
  'json',
  'xml',
  'yaml',
  'yml',
  'csv',
  'log',
  'ini',
  'conf',
  'properties',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'swift',
  'java',
  'kt',
  'kts',
  'dart',
  'py',
  'js',
  'ts',
  'c',
  'cpp',
  'h',
  'css',
  'sh',
  'sql',
};
