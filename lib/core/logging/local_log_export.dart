import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_log_recorder.dart';

/// 导出结果：部分窗口或磁盘采集失败时，UI 必须提示报告不完整。
class LocalLogExportResult {
  const LocalLogExportResult(this.path, {required this.partial});
  final String path;
  final bool partial;
}

/// 本地诊断快照导出；限制读取字节数并逐文件处理，避免日志撑满内存。
class LocalLogExporter {
  static const maxExportBytes = 20 * 1024 * 1024;

  Future<LocalLogExportResult> exportTo(String path) async {
    final recorder = AppLogRecorder.instance;
    var partial = false;
    try {
      final windows = await WindowController.getAll().timeout(
        const Duration(seconds: 2),
      );
      await Future.wait(
        windows
            .where(
              (w) => w.arguments.isNotEmpty && w.windowId != recorder.windowId,
            )
            .map((window) async {
              try {
                final result = await window
                    .invokeMethod('flush_local_logs')
                    .timeout(const Duration(seconds: 2));
                if (result != true) partial = true;
              } catch (_) {
                partial = true;
              }
            }),
      );
    } catch (_) {
      partial = true;
    }
    // 子窗口导出时，主窗口不在子窗口 dispatcher 中，需要走汇总通道刷新。
    if (recorder.windowId.isNotEmpty) {
      try {
        const channel = WindowMethodChannel(
          'any_deck/console_logs',
          mode: ChannelMode.unidirectional,
        );
        final result = await channel
            .invokeMethod('flush_local_logs')
            .timeout(const Duration(seconds: 2));
        if (result != true) partial = true;
      } catch (_) {
        partial = true;
      }
    }
    final store = recorder.store;
    await store?.flush();
    if (store == null ||
        store.lastError != null ||
        store.lostRecords > 0 ||
        recorder.storageError != null) {
      partial = true;
    }
    var files = <File>[];
    String? listingError;
    try {
      files = await store?.filesNewestFirst() ?? <File>[];
    } on FileSystemException catch (error) {
      partial = true;
      listingError = error.toString();
    }
    final outputFile = File(path);
    if (store != null && await store.directory.exists()) {
      final managed = await store.directory.resolveSymbolicLinks();
      final parent = await outputFile.parent.resolveSymbolicLinks();
      final existingTarget = await outputFile.exists()
          ? File(await outputFile.resolveSymbolicLinks()).parent.path
          : parent;
      if (parent == managed || existingTarget == managed) {
        throw StateError('Cannot overwrite managed log files');
      }
    }
    final output = await outputFile.open(mode: FileMode.write);
    try {
      const version = String.fromEnvironment(
        'FLUTTER_BUILD_NAME',
        defaultValue: 'unknown',
      );
      const build = String.fromEnvironment(
        'FLUTTER_BUILD_NUMBER',
        defaultValue: 'unknown',
      );
      await output.writeString(
        'AnyDeck local diagnostic snapshot\n'
        'Captured: ${DateTime.now().toIso8601String()}\n'
        'App: $version+$build\n'
        'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n'
        'Scope: Dart runtime and recorded tool commands; native crash reports excluded.\n'
        'Review personal data before sharing.\n\n',
      );
      var remaining = maxExportBytes;
      for (final file in files) {
        if (remaining <= 0) {
          partial = true;
          break;
        }
        try {
          // 轮转可能在读取期间发生；文件读取长度固定，避免追踪持续增长的文件。
          final length = await file.length();
          final count = length.clamp(
            0,
            remaining < 2 * 1024 * 1024 ? remaining : 2 * 1024 * 1024,
          );
          final start = length - count;
          if (start > 0) partial = true;
          await output.writeString('\n=== ${file.uri.pathSegments.last} ===\n');
          await for (final text
              in file
                  .openRead(start, length)
                  .transform(const Utf8Decoder(allowMalformed: true))) {
            await output.writeString(text);
          }
          remaining -= count;
        } on FileSystemException catch (error) {
          partial = true;
          await output.writeString(
            '\n[File unavailable: ${AppLogRecorder.sanitize(error.toString())}]\n',
          );
        }
      }
      // 磁盘不可用时保留本次会话内存现场，并明确区分于历史文件。
      if (files.isEmpty ||
          store?.lastError != null ||
          (store?.lostRecords ?? 0) > 0) {
        await output.writeString('\n=== Current in-memory logs ===\n');
        final recent = <String>[];
        for (final line in recorder.history.reversed) {
          final size = utf8.encode('$line\n').length;
          if (size > remaining) {
            partial = true;
            break;
          }
          remaining -= size;
          recent.add(line);
        }
        for (final line in recent.reversed) {
          await output.writeString('$line\n');
        }
      }
      final error = store?.lastError ?? recorder.storageError ?? listingError;
      if (error != null) {
        await output.writeString(
          '\n[Storage error: ${AppLogRecorder.sanitize(error)}]\n',
        );
      }
      await output.writeString(
        '\nSnapshot status: ${partial ? 'PARTIAL' : 'COMPLETE'}\n',
      );
      await output.flush();
    } finally {
      await output.close();
    }
    return LocalLogExportResult(path, partial: partial);
  }
}

/// UI 共用导出状态，保存对话框打开期间也阻止重复点击。
final localLogExportProvider = NotifierProvider<LocalLogExportController, bool>(
  LocalLogExportController.new,
);

class LocalLogExportController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<LocalLogExportResult?> capture() async {
    if (state) return null;
    state = true;
    try {
      final location = await getSaveLocation(
        suggestedName:
            'anydeck_logs_${DateTime.now().millisecondsSinceEpoch}.log',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Log', extensions: ['log']),
        ],
      );
      if (location == null) return null;
      return await LocalLogExporter().exportTo(location.path);
    } finally {
      if (ref.mounted) state = false;
    }
  }
}
