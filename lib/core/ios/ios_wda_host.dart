import 'dart:async';
import 'dart:io';
import '../process/tool_path_resolver.dart';
import '../logging/app_log_recorder.dart';

import 'ios_command_service.dart';
import 'ios_wda_http.dart';
import 'ios_wda_process.dart';

/// 主 Isolate 独占 WDA Runner、forward、Session；同设备操作串行，跨设备独立。
class IosWdaHost {
  IosWdaHost({
    IosCommandService? commands,
    String? forwardExecutable,
    this.requestTimeout = const Duration(seconds: 8),
  }) : commands = commands ?? IosCommandService(),
       forwardExecutable = forwardExecutable ?? resolveToolPath('iproxy');
  final IosCommandService commands;
  final String forwardExecutable;
  final Duration requestTimeout;
  final Map<String, _WdaConnection> _connections = {};
  final Set<String> _busy = {};
  final Set<String> _cancelled = {};
  final Map<String, Future<Map<String, dynamic>>> _geometryRequests = {};
  bool _closed = false;

  Future<Map<String, dynamic>> execute(
    String udid,
    String action,
    Map<String, dynamic> args,
  ) {
    if (action != 'geometry') return _execute(udid, action, args);
    // 多窗口共享一次几何查询；输入等待这一次只读请求，避免被后台轮询随机丢弃。
    return _geometryRequests.putIfAbsent(
      udid,
      () => _execute(udid, action, args).whenComplete(() {
        // remove 返回的正是当前 Future；不能将它返回给 whenComplete 形成自等待。
        _geometryRequests.remove(udid);
      }),
    );
  }

  Future<Map<String, dynamic>> _execute(
    String udid,
    String action,
    Map<String, dynamic> args,
  ) async {
    if (_closed) throw StateError('iosControlClosed');
    if (udid.isEmpty) throw ArgumentError('Missing UDID');
    if (action == 'stop') {
      _cancelled.add(udid);
      await _stop(udid);
      return {'ready': false};
    }
    if (action == 'status') {
      final current = _connections[udid];
      return {
        'ready': current?.ready ?? false,
        'busy': _busy.contains(udid),
        ...?current?.geometry,
        'port': current?.http.port,
      };
    }
    if (action != 'geometry' &&
        action != 'start' &&
        _geometryRequests.containsKey(udid)) {
      try {
        await _geometryRequests[udid];
      } catch (_) {}
      if (_closed) throw StateError('iosControlClosed');
    }
    // 拒绝积压输入，避免设备在数秒后才执行历史点击；调用方等待完成再发下一次。
    if (!_busy.add(udid)) throw StateError('iosControlBusy');
    try {
      if (action == 'start') {
        _cancelled.remove(udid);
        return await _start(udid, args['bundleId'] as String?);
      }
      final connection = _connections[udid];
      if (connection == null || !connection.ready) {
        throw StateError('iosWdaUnavailable');
      }
      final http = connection.http;
      switch (action) {
        case 'geometry':
          if (DateTime.now().difference(connection.geometryAt).inMilliseconds >
              500) {
            connection.geometry = await http.geometry();
            connection.geometryAt = DateTime.now();
          }
          return {
            'ready':
                identical(_connections[udid], connection) && connection.ready,
            ...connection.geometry,
          };
        case 'tap':
          await http.gesture(_number(args, 'x'), _number(args, 'y'));
        case 'swipe':
          await http.gesture(
            _number(args, 'fromX'),
            _number(args, 'fromY'),
            toX: _number(args, 'toX'),
            toY: _number(args, 'toY'),
            durationMs: (args['durationMs'] as num?)?.toInt() ?? 400,
          );
        case 'text':
          await http.request(
            http.path('/wda/keys'),
            method: 'POST',
            body: {
              'value': [args['text'] as String],
            },
          );
        case 'button':
          final name = args['name'] as String;
          await http.request(
            name == 'home' ? '/wda/homescreen' : http.path('/wda/pressButton'),
            method: 'POST',
            body: name == 'home' ? null : {'name': name},
          );
        case 'lock':
          await http.request('/wda/lock', method: 'POST');
        case 'source':
          return {'value': (await http.request(http.path('/source')))['value']};
        default:
          throw ArgumentError('Unknown iOS control action: $action');
      }
      return {
        'ready': identical(_connections[udid], connection) && connection.ready,
      };
    } on IosWdaRequestError catch (error) {
      if (error.invalidSession) {
        await _stop(udid);
        throw StateError('iosWdaConnectionLost');
      }
      rethrow;
    } on SocketException {
      await _stop(udid);
      rethrow;
    } on TimeoutException {
      final connection = _connections[udid];
      // 单次慢请求不代表 Runner 已退出。只探测会话，绝不重放可能已执行的输入。
      var recovered = false;
      if (connection?.ready == true) {
        try {
          await connection!.http.request(connection.http.path(''));
          recovered = identical(_connections[udid], connection);
        } catch (_) {}
      }
      AppLogRecorder.instance.record(
        'WDA $action timed out; session responsive=$recovered',
        tag: 'ios-control',
        level: 'W',
      );
      if (!recovered) await _stop(udid);
      throw StateError(
        recovered ? 'iosWdaRequestTimeout' : 'iosWdaConnectionLost',
      );
    } finally {
      _busy.remove(udid);
    }
  }

  static double _number(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is! num || !value.isFinite) throw ArgumentError('Invalid $key');
    return value.toDouble();
  }

  Future<Map<String, dynamic>> _start(String udid, String? bundleId) async {
    final existing = _connections[udid];
    if (existing?.ready == true) return {'ready': true, ...existing!.geometry};
    await _stop(udid);
    final apps = await commands.listApps(udid);
    void checkCancelled() {
      if (_closed || _cancelled.contains(udid)) {
        throw StateError('iosControlClosed');
      }
    }

    checkCancelled();
    final selected = bundleId?.trim();
    final candidates = apps
        .where(
          (a) => selected != null && selected.isNotEmpty
              ? a.bundleId == selected
              : a.bundleId.toLowerCase().contains('webdriveragent') &&
                    a.bundleId.endsWith('.xctrunner'),
        )
        .toList();
    if (candidates.length != 1) throw StateError('iosWdaRunnerMissing');
    final runner = candidates.single.bundleId;
    // iOS 15 XCTest 依赖 Developer Disk Image；安装 Runner 本身不代表可以启动测试。
    final image = await commands.run([
      'image',
      'auto',
      '--udid=$udid',
    ], timeout: const Duration(seconds: 60));
    checkCancelled();
    if (!image.isSuccess) {
      throw StateError('WDA developer image: ${image.message}');
    }
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final connection = _WdaConnection(
      IosWdaHttp(port, timeout: requestTimeout),
    );
    _connections[udid] = connection;
    try {
      // go-ios v1.2 forward 固定监听 0.0.0.0；iproxy 显式限定 loopback + USB。
      try {
        connection.forward = await IosWdaProcess.start(forwardExecutable, [
          '--source',
          '127.0.0.1',
          '--local',
          '--udid',
          udid,
          '$port:8100',
        ]);
      } on ProcessException catch (error) {
        throw StateError('iosWdaProxyMissing: ${error.message}');
      }
      checkCancelled();
      connection.runner = await IosWdaProcess.start(commands.executable, [
        'runwda',
        '--bundleid=$runner',
        '--testrunnerbundleid=$runner',
        '--xctestconfig=WebDriverAgentRunner.xctest',
        '--udid=$udid',
      ]);
      checkCancelled();
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      Object? lastError;
      var responding = false;
      while (!_closed &&
          !_cancelled.contains(udid) &&
          DateTime.now().isBefore(deadline)) {
        if (connection.forward?.exitCode != null ||
            connection.runner?.exitCode != null) {
          throw StateError(
            'WDA process exited: ${connection.runner?.log}\n${connection.forward?.log}',
          );
        }
        try {
          await connection.http.request('/status');
          responding = true;
          break;
        } catch (error) {
          lastError = error;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      checkCancelled();
      if (!responding) {
        throw StateError(
          'WDA startup failed: $lastError\n${connection.runner?.log}',
        );
      }
      await connection.http.createSession();
      connection.geometry = await connection.http.geometry();
      connection.geometryAt = DateTime.now();
      checkCancelled();
      connection.ready = true;
      // CLI 退出立即失效；旧进程回调不能误清理重连后的会话。
      for (final child in [connection.runner!, connection.forward!]) {
        unawaited(
          child.process.exitCode.then((code) async {
            if (identical(_connections[udid], connection)) {
              AppLogRecorder.instance.record(
                'WDA ${identical(child, connection.runner) ? 'runner' : 'forward'} exited ($code)',
                tag: 'ios-control',
                level: 'W',
              );
              await _stop(udid);
            }
          }),
        );
      }
      return {'ready': true, ...connection.geometry, 'port': port};
    } catch (_) {
      if (identical(_connections[udid], connection)) _connections.remove(udid);
      // stop 可能发生在 Process.start 返回之前，必须回收随后才取得的句柄。
      await _disposeConnection(connection);
      rethrow;
    }
  }

  Future<void> _stop(String udid) async {
    final connection = _connections.remove(udid);
    if (connection == null) return;
    await _disposeConnection(connection);
  }

  Future<void> _disposeConnection(_WdaConnection connection) async {
    connection.ready = false;
    connection.http.close();
    await Future.wait([
      if (connection.runner != null) connection.runner!.stop(),
      if (connection.forward != null) connection.forward!.stop(),
    ]);
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait(_connections.keys.toList().map(_stop));
  }
}

/// 会话数据只存在主引擎，子窗口通过 gateway 访问，避免重复创建 WDA Session。
class _WdaConnection {
  _WdaConnection(this.http);
  final IosWdaHttp http;
  IosWdaProcess? runner;
  IosWdaProcess? forward;
  bool ready = false;
  Map<String, dynamic> geometry = {};
  DateTime geometryAt = DateTime.fromMillisecondsSinceEpoch(0);
}
