import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../adb/adb_device.dart';
import '../process/tool_path_resolver.dart';
import 'ios_mirror_session.dart';

/// 负责管理 go-ios 进程、解析设备列表以及管理 iOS 投屏会话。
class IosDeviceService {
  IosDeviceService({
    void Function(String message, {String tag, String level})? onLog,
  }) : _onLog = onLog;

  final void Function(String message, {String tag, String level})? _onLog;
  final Map<String, IosMirrorSession> _sessions = {};

  /// 检索可用 go-ios 二进制路径。
  String _resolveBinary() {
    final pathIos = resolveToolPath('ios');
    if (pathIos != 'ios' && File(pathIos).existsSync()) {
      return pathIos;
    }
    final pathGoIos = resolveToolPath('go-ios');
    if (pathGoIos != 'go-ios' && File(pathGoIos).existsSync()) {
      return pathGoIos;
    }
    return 'ios'; // 回退至系统 PATH
  }

  /// 获取已连接的 iOS 设备列表。
  Future<List<AdbDevice>> listDevices() async {
    final exe = _resolveBinary();
    try {
      final result = await Process.run(exe, ['list', '--details']);
      if (result.exitCode != 0) {
        _onLog?.call('go-ios list 失败，退出码: ${result.exitCode}, stderr: ${result.stderr}', tag: 'ios', level: 'W');
        return [];
      }
      
      final lines = LineSplitter.split(result.stdout);
      final devices = <AdbDevice>[];
      
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        
        try {
          final dynamic decoded = jsonDecode(trimmed);
          List<dynamic> list = [];
          if (decoded is List) {
            list = decoded;
          } else if (decoded is Map) {
            final deviceList = decoded['deviceList'] ?? decoded['devices'] ?? decoded['data'];
            if (deviceList is List) {
              list = deviceList;
            } else if (decoded.containsKey('UniqueIdentifier') || decoded.containsKey('Udid') || decoded.containsKey('udid')) {
              list = [decoded];
            }
          }

          for (final item in list) {
            if (item is Map) {
              final udid = (item['Udid'] ?? item['udid'] ?? item['UniqueIdentifier'] ?? '').toString();
              if (udid.isEmpty) continue;

              final name = (item['ProductName'] ?? item['name'] ?? 'iPhone').toString();
              final type = (item['ProductType'] ?? item['type'] ?? '').toString();
              final version = (item['ProductVersion'] ?? item['version'] ?? 'iOS').toString();
              
              final modelName = type.isNotEmpty ? '$name ($type)' : name;
              devices.add(AdbDevice(
                id: udid,
                status: 'device',
                model: modelName,
                product: version,
                transportId: '',
                isIos: true,
              ));
            }
          }
        } catch (_) {
          // 忽略非目标 JSON 结构或警告日志行的解析失败
        }
      }
      return devices;
    } on ProcessException catch (e) {
      _onLog?.call('未能启动 go-ios 进程，请检查是否正确安装：${e.message}', tag: 'ios', level: 'W');
    } catch (e) {
      _onLog?.call('解析 go-ios 设备列表失败: $e', tag: 'ios', level: 'E');
    }
    return [];
  }

  /// 检测某个设备是否处于活跃投屏会话中。
  bool isActive(String udid) => _sessions.containsKey(udid);

  /// 获取指定设备的流本地端口。
  int? getPort(String udid) => _sessions[udid]?.port;

  /// 获取指定设备的投屏流进程。
  Process? getStreamProcess(String udid) => _sessions[udid]?.process;

  /// 开始 iOS 设备 USB 投屏（启动 MJPEG 本地流服务）。
  Future<int> startMirroring({required String udid, required int port}) async {
    if (_sessions.containsKey(udid)) {
      return _sessions[udid]!.port;
    }

    final exe = _resolveBinary();
    
    // 强制使用固定的 3333 端口，因为当前 go-ios screenshot --stream 存在无法通过 --port 修改绑定端口的 Bug，固定为 3333
    const targetPort = 3333;
    final args = ['screenshot', '--stream', '--port=$targetPort', '--udid=$udid'];
    _onLog?.call('启动 iOS 投屏进程: $exe ${args.join(' ')}', tag: 'ios', level: 'I');

    // 在启动前，清理占用 3333 端口的残留进程以防止 bind 失败
    try {
      final lsofResult = await Process.run('lsof', ['-t', '-i', ':3333']);
      if (lsofResult.exitCode == 0) {
        final pidStr = lsofResult.stdout.toString().trim();
        if (pidStr.isNotEmpty) {
          final pids = pidStr.split('\n');
          for (final pid in pids) {
            final parsedPid = int.tryParse(pid.trim());
            if (parsedPid != null) {
              _onLog?.call('清理占用 3333 端口的残留进程 PID: $parsedPid', tag: 'ios', level: 'I');
              Process.killPid(parsedPid, ProcessSignal.sigkill);
            }
          }
        }
      }
    } catch (e) {
      _onLog?.call('检查或清理 3333 端口失败: $e', tag: 'ios', level: 'W');
    }

    try {
      final process = await Process.start(exe, args);
      
      // 监听错误输出，记录日志
      process.stderr.transform(utf8.decoder).listen((data) {
        _onLog?.call('[go-ios stderr] ${data.trim()}', tag: 'ios', level: 'W');
      });

      // 注册新会话
      final session = IosMirrorSession(
        udid: udid,
        port: targetPort,
        process: process,
        startedAt: DateTime.now(),
      );
      _sessions[udid] = session;

      // 稍微等待进程完全启动并绑定端口
      await Future.delayed(const Duration(milliseconds: 600));
      return targetPort;
    } catch (e) {
      _onLog?.call('启动 go-ios 投屏服务出错: $e', tag: 'ios', level: 'E');
      rethrow;
    }
  }

  /// 停止 iOS 设备的投屏会话并清理进程。
  Future<void> stopMirroring(String udid) async {
    final session = _sessions.remove(udid);
    if (session == null) return;

    _onLog?.call('正在停止 iOS 投屏进程，UDID: $udid', tag: 'ios', level: 'I');
    session.process.kill();
    await session.process.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        session.process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  /// 停止所有活跃会话。
  void stopAll() {
    final udids = List<String>.from(_sessions.keys);
    for (final udid in udids) {
      stopMirroring(udid);
    }
  }
}
