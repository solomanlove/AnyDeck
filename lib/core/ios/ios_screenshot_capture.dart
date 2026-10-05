import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../adb/adb_result.dart';

/// 截图恢复流程复用带超时和进程回收的命令执行器。
typedef IosScreenshotCommand =
    Future<AdbResult> Function(List<String> args, {Duration timeout});

/// 单次截图在缺少开发者镜像时自动挂载并重试，按设备合并并发请求。
class IosScreenshotCapture {
  IosScreenshotCapture(this._run);

  final IosScreenshotCommand _run;
  final _pending = <String, Future<Uint8List>>{};

  Future<Uint8List> capture(String udid) {
    return _pending.putIfAbsent(udid, () async {
      try {
        return await _capture(udid);
      } finally {
        _pending.remove(udid);
      }
    });
  }

  Future<Uint8List> _capture(String udid) async {
    final directory = await Directory.systemTemp.createTemp('anydeck_ios_');
    final file = File('${directory.path}/screenshot.png');
    final args = ['screenshot', '--output=${file.path}', '--udid=$udid'];
    try {
      var result = await _run(args);
      if (!result.isSuccess && _needsDeveloperImage(result)) {
        // 首次下载镜像可能较慢；复用 run 的超时终止机制，不启动常驻进程。
        final mounted = await _run([
          'image',
          'auto',
          '--udid=$udid',
        ], timeout: const Duration(minutes: 5));
        if (!mounted.isSuccess) throw Exception(_errorDetail(mounted));
        // 删除失败调用留下的文件，以重试结果而非旧文件判断截图是否成功。
        if (await file.exists()) await file.delete();
        result = await _run(args);
      }
      if (!result.isSuccess) throw Exception(_errorDetail(result));
      if (!await file.exists() || await file.length() == 0) {
        throw Exception('go-ios 未生成截图文件');
      }
      return await file.readAsBytes();
    } finally {
      try {
        await directory.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 只响应开发服务缺失；普通 tunnel WARN、断连或权限错误不触发挂载。
  static bool _needsDeveloperImage(AdbResult result) {
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return output.contains('developer disk image must be mounted') ||
        output.contains('have you mounted the developer image') ||
        (output.contains('invalidservice') &&
            (output.contains('dvtsocketproxy') ||
                output.contains('dvtsecuresocketproxy') ||
                output.contains('screenshotr')));
  }

  /// 优先展示 ERROR/FATAL 的 err，避免 stdout 的 tunnel 警告遮蔽 stderr。
  static String _errorDetail(AdbResult result) {
    final lines = const LineSplitter().convert(
      '${result.stdout}\n${result.stderr}',
    );
    for (final line in lines.reversed) {
      try {
        final value = jsonDecode(line);
        if (value is! Map) continue;
        final level = value['level']?.toString().toLowerCase();
        if (level != 'error' && level != 'fatal') continue;
        final detail = value['err'] ?? value['error'] ?? value['msg'];
        if (detail != null && detail.toString().trim().isNotEmpty) {
          return detail.toString();
        }
      } catch (_) {}
    }
    return result.stderr.trim().isNotEmpty
        ? result.stderr.trim()
        : result.message;
  }
}
