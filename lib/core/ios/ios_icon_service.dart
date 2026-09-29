import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'ios_command_service.dart';

/// 单次批量图标请求的取消句柄，由页面 Provider 在销毁时释放。
class IosIconRequest {
  bool cancelled = false;
  Process? process;

  void cancel() {
    cancelled = true;
    process?.kill(ProcessSignal.sigkill);
  }
}

/// iOS 应用图标管理服务，负责通过 SpringBoard Services (com.apple.springboardservices)
/// 提取已连接设备的真实应用高清图标，并缓存在本地磁盘。
class IosIconService {
  IosIconService();

  static const String _helperAssetPath = 'assets/ios/ios_icon_helper.py';
  final Map<String, Map<String, String>> _memoryCache =
      {}; // udid -> (bundleId -> iconPath)

  /// 获取或释放 helper 脚本到本地可执行环境
  Future<File> _resolveHelperScript() async {
    // 1. 优先使用本地源码工程中的脚本
    final localFile = File(_helperAssetPath);
    if (await localFile.exists()) {
      return localFile;
    }

    // 2. 打包后从 rootBundle 提取至临时目录
    final tempDir = Directory(
      '${(await getTemporaryDirectory()).path}/any_deck_helper',
    );
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    final scriptFile = File('${tempDir.path}/ios_icon_helper.py');
    try {
      final data = await rootBundle.load(_helperAssetPath);
      await scriptFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    } catch (_) {}

    return scriptFile;
  }

  /// 获取图标本地存储目录
  Future<Directory> _getCacheDir(String udid) async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/ios_app_icons/$udid');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 同步或快速获取已缓存的图标文件路径
  String? getCachedIconPath(String udid, String bundleId) {
    return _memoryCache[udid]?[bundleId];
  }

  /// 批量获取并缓存指定设备的 App 图标
  Future<Map<String, String>> fetchIcons(
    String udid,
    List<String> bundleIds, {
    IosIconRequest? request,
  }) async {
    request ??= IosIconRequest();
    if (bundleIds.isEmpty || !RegExp(r'^[A-Za-z0-9-]+$').hasMatch(udid)) {
      return const {};
    }

    final cacheDir = await _getCacheDir(udid);
    final results = <String, String>{};
    final toFetch = <String>[];

    // 1. 先命中已有磁盘缓存
    for (final bid in bundleIds) {
      if (request.cancelled) return results;
      // Bundle ID 参与缓存文件名，拒绝目录分隔符及特殊路径。
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(bid)) continue;
      final cachedPath = _memoryCache[udid]?[bid];
      if (cachedPath != null && await File(cachedPath).exists()) {
        results[bid] = cachedPath;
        continue;
      }

      final file = File('${cacheDir.path}/$bid.png');
      if (await file.exists() && (await file.length()) > 0) {
        results[bid] = file.path;
        _memoryCache.putIfAbsent(udid, () => {})[bid] = file.path;
      } else {
        toFetch.add(bid);
      }
    }

    if (toFetch.isEmpty) {
      return results;
    }

    // 2. 执行 helper 脚本向 SpringBoard 请求未缓存的图标
    try {
      final script = await _resolveHelperScript();
      if (!await script.exists()) {
        return results;
      }

      // 分批拉取，每批最多 30 个，避免命令行超长或单次超时
      const batchSize = 30;
      for (var i = 0; i < toFetch.length; i += batchSize) {
        if (request.cancelled) break;
        final chunk = toFetch.skip(i).take(batchSize).toList();
        final process = await Process.start('python3', [
          script.path,
          '--udid=$udid',
          '--bundle-ids=${chunk.join(',')}',
          '--output-dir=${cacheDir.path}',
          '--ios-path=${IosCommandService().executable}',
        ]);
        request.process = process;
        final stdoutFuture = process.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .join();
        final stderrFuture = process.stderr.drain<void>();
        if (request.cancelled) process.kill(ProcessSignal.sigkill);
        int exitCode;
        try {
          exitCode = await process.exitCode.timeout(
            const Duration(seconds: 15),
          );
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
          break;
        } finally {
          request.process = null;
        }
        await stderrFuture;

        if (exitCode == 0 && !request.cancelled) {
          final stdoutStr = (await stdoutFuture).trim();
          for (final line in const LineSplitter().convert(stdoutStr)) {
            final trimmed = line.trim();
            if (!trimmed.startsWith('{') || !trimmed.contains('"saved"')) {
              continue;
            }
            try {
              final json = jsonDecode(trimmed);
              if (json is Map && json['saved'] is List) {
                for (final item in json['saved']) {
                  final bid = item['bundleId']?.toString();
                  final path = item['path']?.toString();
                  if (bid != null &&
                      chunk.contains(bid) &&
                      path != null &&
                      path == '${cacheDir.path}/$bid.png' &&
                      await File(path).exists()) {
                    results[bid] = path;
                    _memoryCache.putIfAbsent(udid, () => {})[bid] = path;
                  }
                }
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    return results;
  }
}

/// 全局 iOS 图标服务提供者
final iosIconServiceProvider = Provider<IosIconService>((ref) {
  return IosIconService();
});
