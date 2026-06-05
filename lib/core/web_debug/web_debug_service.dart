import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../adb/adb_service.dart';
import 'webpage_target.dart';

/// 安卓 WebView 及 Chrome 远程网页调试服务。
class WebDebugService {
  WebDebugService(this._adb);

  final AdbService _adb;

  /// 缓存已转发的端口映射，格式为：`deviceId:socketName` -> `localPort`
  final Map<String, int> _forwardedPorts = {};

  /// 缓存进程名以减少 adb 请求，格式为：`pid` -> `packageName`
  final Map<String, String> _packageNameCache = {};

  /// 扫描指定设备上所有的 debug 网页目标。
  Future<List<WebpageTarget>> scanTargets(String deviceId) async {
    // 1. 读取手机的 unix sockets 列表以查找 devtools
    final result = await _adb.shellArgs(deviceId, ['cat', '/proc/net/unix']);
    if (!result.isSuccess) {
      return [];
    }

    final activeSockets = <String>{};
    final lines = result.stdout.split('\n');
    for (var line in lines) {
      line = line.trim();
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 8) {
        final path = parts.last;
        // 如果是以 @ 开头，且包含 devtools_remote 的套接字
        if (path.startsWith('@') && path.contains('devtools_remote')) {
          activeSockets.add(path.substring(1)); // 剥离 @
        }
      }
    }

    // 2. 清理已离线或已关闭 sockets 的端口转发，避免端口残留泄露
    final keyPrefix = '$deviceId:';
    final keysToRemove = <String>[];
    _forwardedPorts.forEach((key, port) {
      if (key.startsWith(keyPrefix)) {
        final socketName = key.substring(keyPrefix.length);
        if (!activeSockets.contains(socketName)) {
          keysToRemove.add(key);
        }
      }
    });

    for (final key in keysToRemove) {
      final port = _forwardedPorts.remove(key);
      if (port != null) {
        try {
          await _adb.run(['-s', deviceId, 'forward', '--remove', 'tcp:$port']);
        } catch (_) {}
      }
    }

    // 3. 逐个请求 sockets 列表并组装网页目标
    final allTargets = <WebpageTarget>[];
    for (final socketName in activeSockets) {
      // 提取 PID 并尝试加载包名
      final pidMatch = RegExp(r'\d+$').firstMatch(socketName);
      final pid = pidMatch?.group(0) ?? '';
      final packageName = pid.isNotEmpty
          ? await _getPackageName(deviceId, pid)
          : '未知应用';

      try {
        await _removeStaleForwards(deviceId, socketName);
        final port = await _getOrForwardPort(deviceId, socketName);
        final rawTargets = await _fetchTargets(port);
        for (final raw in rawTargets) {
          allTargets.add(
            WebpageTarget.fromJson(
              json: raw,
              packageName: packageName,
              pid: pid,
              socketName: socketName,
              port: port,
            ),
          );
        }
      } catch (_) {
        // 如果单个 socket 转发或数据获取失败，跳过以避免阻断其他 sockets
      }
    }

    return allTargets;
  }

  /// 获取或建立一个端口转发。
  Future<int> _getOrForwardPort(String deviceId, String socketName) async {
    final key = '$deviceId:$socketName';
    if (_forwardedPorts.containsKey(key)) {
      return _forwardedPorts[key]!;
    }

    final port = await _findFreePort();
    final result = await _adb.run([
      '-s',
      deviceId,
      'forward',
      'tcp:$port',
      'localabstract:$socketName',
    ]);
    if (result.isSuccess) {
      _forwardedPorts[key] = port;
      return port;
    } else {
      throw Exception('Adb forward failed: ${result.message}');
    }
  }

  /// 清理同一 socket 的历史端口转发，避免旧 App 实例或旧刷新残留影响连接。
  Future<void> _removeStaleForwards(String deviceId, String socketName) async {
    final result = await _adb.run(['-s', deviceId, 'forward', '--list']);
    if (!result.isSuccess) {
      return;
    }

    final knownPort = _forwardedPorts['$deviceId:$socketName'];
    for (final line in result.stdout.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 3 || parts[0] != deviceId) {
        continue;
      }
      final local = parts[1];
      final remote = parts[2];
      if (remote != 'localabstract:$socketName' || !local.startsWith('tcp:')) {
        continue;
      }
      final port = int.tryParse(local.substring(4));
      if (port == null || port == knownPort) {
        continue;
      }
      try {
        await _adb.run(['-s', deviceId, 'forward', '--remove', local]);
      } catch (_) {}
    }
  }

  /// 在本机上寻找一个闲置的 TCP 端口。
  Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// 访问已转发端口的 /json/list，加载其中的 web targets 列表。
  Future<List<Map<String, dynamic>>> _fetchTargets(int port) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/json/list'),
      );
      final response = await request.close();
      if (response.statusCode == 200) {
        final content = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          return List<Map<String, dynamic>>.from(decoded);
        }
      }
    } catch (_) {
      // 兼容一些老版本 Chrome/WebView 的 /json 接口
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/json'),
        );
        final response = await request.close();
        if (response.statusCode == 200) {
          final content = await response.transform(utf8.decoder).join();
          final decoded = jsonDecode(content);
          if (decoded is List) {
            return List<Map<String, dynamic>>.from(decoded);
          }
        }
      } catch (_) {}
    } finally {
      client.close();
    }
    return [];
  }

  /// 获取 PID 对应的包名并缓存。
  Future<String> _getPackageName(String deviceId, String pid) async {
    if (_packageNameCache.containsKey(pid)) {
      return _packageNameCache[pid]!;
    }
    try {
      final result = await _adb.shellArgs(deviceId, [
        'cat',
        '/proc/$pid/cmdline',
      ]);
      if (result.isSuccess && result.stdout.trim().isNotEmpty) {
        final name = result.stdout.split('\x00').first.trim();
        if (name.isNotEmpty) {
          _packageNameCache[pid] = name;
          return name;
        }
      }
    } catch (_) {}
    return '未知应用';
  }

  /// 移除某个设备建立的所有端口转发规则。
  Future<void> removeForwards(String deviceId) async {
    final keyPrefix = '$deviceId:';
    final keysToRemove = <String>[];
    _forwardedPorts.forEach((key, port) {
      if (key.startsWith(keyPrefix)) {
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      final port = _forwardedPorts.remove(key);
      if (port != null) {
        try {
          await _adb.run(['-s', deviceId, 'forward', '--remove', 'tcp:$port']);
        } catch (_) {}
      }
    }
  }

  /// 打开调试器检查特定的网页。
  Future<void> openInspector(
    WebpageTarget target,
    bool useLocalDebugger,
  ) async {
    await openBrowser(buildInspectorUrl(target, useLocalDebugger));
  }

  /// 构造本机可连接的 DevTools 调试 URL。
  String buildInspectorUrl(WebpageTarget target, bool useLocalDebugger) {
    final wsEndpoint = _localWebSocketEndpoint(target);
    if (useLocalDebugger) {
      // 使用本地内置调试器 URL
      return 'devtools://devtools/bundled/inspector.html?ws=$wsEndpoint';
    }

    if (target.devtoolsFrontendUrl.isNotEmpty) {
      // Android/WebView 常返回 /devtools/... 相对路径，必须补成本机转发端口。
      return _replaceWebSocketEndpoint(
        _normalizeFrontendUrl(target.devtoolsFrontendUrl, target.port),
        wsEndpoint,
      );
    }

    // 缺省的在线 DevTools 调试前端
    return 'https://chrome-devtools-frontend.appspot.com/serve_rev/@d1ef8f1176b6ef009d73d6e53a32f6b3cf59a68e/inspector.html?ws=$wsEndpoint';
  }

  String _localWebSocketEndpoint(WebpageTarget target) {
    final parsed = Uri.tryParse(target.webSocketDebuggerUrl);
    final path = parsed != null && parsed.path.isNotEmpty
        ? parsed.path
        : '/devtools/page/${target.id}';
    final query = parsed != null && parsed.hasQuery ? '?${parsed.query}' : '';
    return '127.0.0.1:${target.port}$path$query';
  }

  String _normalizeFrontendUrl(String url, int port) {
    if (url.startsWith('/')) {
      return 'http://127.0.0.1:$port$url';
    }
    if (url.startsWith('devtools://')) {
      return url;
    }

    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) {
      return url;
    }
    return 'http://127.0.0.1:$port/$url';
  }

  String _replaceWebSocketEndpoint(String url, String wsEndpoint) {
    final wsPattern = RegExp(r'([?&]ws=)([^&]+)');
    if (wsPattern.hasMatch(url)) {
      return url.replaceFirstMapped(
        wsPattern,
        (match) => '${match.group(1)}$wsEndpoint',
      );
    }

    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}ws=$wsEndpoint';
  }

  /// 在本机的默认浏览器中打开指定链接。
  Future<void> openBrowser(String url) async {
    late final ProcessResult result;
    if (Platform.isMacOS) {
      if (url.startsWith('devtools://')) {
        result = await Process.run('open', ['-a', 'Google Chrome', url]);
      } else {
        result = await Process.run('open', [url]);
      }
    } else if (Platform.isWindows) {
      if (url.startsWith('devtools://')) {
        result = await Process.run('cmd', ['/c', 'start', 'chrome', url]);
      } else {
        result = await Process.run('cmd', ['/c', 'start', '', url]);
      }
    } else if (Platform.isLinux) {
      if (url.startsWith('devtools://')) {
        result = await Process.run('google-chrome', [url]);
      } else {
        result = await Process.run('xdg-open', [url]);
      }
    } else {
      throw UnsupportedError('当前平台不支持自动打开浏览器');
    }

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      final message = stderr.isNotEmpty
          ? stderr
          : stdout.isNotEmpty
          ? stdout
          : 'exit code ${result.exitCode}';
      throw Exception(message);
    }
  }
}
