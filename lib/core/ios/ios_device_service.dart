import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../adb/adb_device.dart';
import '../adb/adb_result.dart';
import '../dal/rust_dal_bridge.dart';
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
    if (RustDalBridge.instance.isAvailable) {
      final nativeList = await RustDalBridge.instance.listIosDevices();
      if (nativeList.isNotEmpty) {
        return nativeList.map((item) {
          final udid = (item['udid'] ?? '').toString();
          final name = (item['name'] ?? 'iPhone').toString();
          final model = (item['model'] ?? '').toString();
          final version = (item['version'] ?? 'iOS').toString();
          final modelName = model.isNotEmpty ? '$name ($model)' : name;
          return AdbDevice(
            id: udid,
            status: 'device',
            model: modelName,
            product: version,
            transportId: '',
            isIos: true,
          );
        }).toList();
      }
    }

    final exe = _resolveBinary();
    try {
      final result = await Process.run(exe, ['list', '--details']);
      if (result.exitCode != 0) {
        _onLog?.call('go-ios list 失败，退出码: ${result.exitCode}, stderr: ${result.stderr}', tag: 'ios', level: 'W');
        return [];
      }
      
      return parseDeviceListOutput(result.stdout);
    } on ProcessException catch (e) {
      _onLog?.call('未能启动 go-ios 进程，请检查是否正确安装：${e.message}', tag: 'ios', level: 'W');
    } catch (e) {
      _onLog?.call('解析 go-ios 设备列表失败: $e', tag: 'ios', level: 'E');
    }
    return [];
  }

  /// 解析 go-ios 输出的设备列表，过滤日志并按 UDID 去重。
  static List<AdbDevice> parseDeviceListOutput(String output) {
    final lines = LineSplitter.split(output);
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
          final deviceList =
              decoded['deviceList'] ?? decoded['devices'] ?? decoded['data'];
          if (deviceList is List) {
            list = deviceList;
          } else if (decoded.containsKey('UniqueIdentifier') ||
              decoded.containsKey('Udid') ||
              decoded.containsKey('udid')) {
            list = [decoded];
          }
        }

        for (final item in list) {
          if (item is Map) {
            final udid = (item['Udid'] ??
                    item['udid'] ??
                    item['UniqueIdentifier'] ??
                    '')
                .toString();
            if (udid.isEmpty) continue;

            // 避免同一设备由于同时连接 USB 与 WiFi 输出重复项
            if (devices.any((d) => d.id == udid)) continue;

            final name =
                (item['ProductName'] ?? item['name'] ?? 'iPhone').toString();
            final type = (item['ProductType'] ?? item['type'] ?? '').toString();
            final version =
                (item['ProductVersion'] ?? item['version'] ?? 'iOS').toString();

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
  }

  /// 检测某个设备是否处于活跃投屏会话中。
  bool isActive(String udid) => _sessions.containsKey(udid);

  /// 获取指定设备的流本地端口。
  int? getPort(String udid) => _sessions[udid]?.port;

  /// 获取指定设备的投屏流进程。
  Process? getStreamProcess(String udid) => _sessions[udid]?.process;

  /// 自动下载并挂载 iOS 开发者镜像 (Developer Disk Image)
  Future<AdbResult> mountDeveloperImage(String udid) async {
    final exe = _resolveBinary();
    _onLog?.call('正在为 iOS 设备挂载开发者镜像: $exe image auto --udid=$udid', tag: 'ios', level: 'I');
    try {
      final result = await Process.run(exe, ['image', 'auto', '--udid=$udid']).timeout(const Duration(seconds: 45));
      final combined = '${result.stdout}\n${result.stderr}';
      if (combined.contains('DeviceLocked') ||
          combined.contains('failed to read response for \'ReceiveBytes\'') ||
          combined.contains('failed to read message length: EOF') ||
          combined.contains('wrong payload length')) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: 'iPhone 处于锁屏状态，请在手机上输入密码解锁屏幕并保持亮屏，然后重试',
        );
      }
      
      // 检查挂载结果
      final listRes = await Process.run(exe, ['image', 'list', '--udid=$udid']);
      final listOut = listRes.stdout.toString();
      if (listRes.exitCode == 0 && !listOut.contains('"none"') && !listOut.contains('[]')) {
        _onLog?.call('开发者镜像挂载成功', tag: 'ios', level: 'I');
        return const AdbResult(exitCode: 0, stdout: '开发者镜像挂载成功', stderr: '');
      }

      String errorDetail = '挂载开发者镜像失败';
      if (combined.contains('"err":')) {
        try {
          final lines = LineSplitter.split(combined);
          for (final line in lines) {
            if (line.contains('"err":')) {
              final decoded = jsonDecode(line);
              if (decoded is Map && decoded['err'] != null) {
                errorDetail = decoded['err'].toString();
                break;
              }
            }
          }
        } catch (_) {}
      }

      return AdbResult(
        exitCode: 1,
        stdout: result.stdout.toString(),
        stderr: errorDetail,
      );
    } catch (e) {
      return AdbResult(exitCode: 1, stdout: '', stderr: '挂载开发者镜像失败: $e');
    }
  }

  /// 开始 iOS 设备 USB 投屏（启动 MJPEG 本地流服务）。
  Future<int> startMirroring({
    required String udid,
    required int port,
    bool retryOnMountFail = true,
  }) async {
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
      final stderrList = <String>[];
      final stdoutList = <String>[];

      // 监听错误输出与标准输出，记录日志并收集启动错误
      process.stderr.transform(utf8.decoder).listen((data) {
        final trimmed = data.trim();
        if (trimmed.isNotEmpty) {
          stderrList.add(trimmed);
          _onLog?.call('[go-ios stderr] $trimmed', tag: 'ios', level: 'W');
        }
      });
      process.stdout.transform(utf8.decoder).listen((data) {
        final trimmed = data.trim();
        if (trimmed.isNotEmpty) {
          stdoutList.add(trimmed);
          _onLog?.call('[go-ios stdout] $trimmed', tag: 'ios', level: 'D');
        }
      });

      // 关键：轮询检查端口是否已就绪或进程是否因报错退出（最多等待 2500ms）
      var isExited = false;
      int? earlyExitCode;
      process.exitCode.then((code) {
        isExited = true;
        earlyExitCode = code;
      });

      final deadline = DateTime.now().add(const Duration(milliseconds: 2500));
      var portReady = false;
      while (!isExited && DateTime.now().isBefore(deadline)) {
        try {
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            targetPort,
            timeout: const Duration(milliseconds: 200),
          );
          await socket.close();
          portReady = true;
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }

      if (isExited || !portReady) {
        final combinedOutput = '${stdoutList.join(" ")} ${stderrList.join(" ")}';
        
        // 情况 A: 未挂载开发者镜像
        if (retryOnMountFail &&
            (combinedOutput.contains('the Developer Disk Image must be mounted') ||
             combinedOutput.contains('DVTSecureSocketProxy') ||
             combinedOutput.contains('InvalidService'))) {
          _onLog?.call('iOS 设备未挂载开发者镜像，正在自动尝试挂载...', tag: 'ios', level: 'I');
          final mountRes = await mountDeveloperImage(udid);
          if (mountRes.isSuccess) {
            _onLog?.call('开发者镜像挂载成功，正在重新启动投屏...', tag: 'ios', level: 'I');
            return await startMirroring(udid: udid, port: port, retryOnMountFail: false);
          } else {
            throw Exception(mountRes.message);
          }
        }

        // 情况 B: 手机屏幕已锁定
        if (combinedOutput.contains('DeviceLocked') ||
            combinedOutput.contains('failed to read response for \'ReceiveBytes\'') ||
            combinedOutput.contains('failed to read message length: EOF') ||
            combinedOutput.contains('wrong payload length')) {
          throw Exception('iPhone 处于锁屏状态，请在手机上输入密码解锁屏幕并保持亮屏，然后重试');
        }

        // 情况 C: 其它具体错误信息提取
        String errorDetail = '';
        for (final line in stderrList.reversed) {
          try {
            final decoded = jsonDecode(line);
            if (decoded is Map && decoded.containsKey('err')) {
              errorDetail = decoded['err'].toString();
              break;
            } else if (decoded is Map && decoded.containsKey('msg')) {
              errorDetail = decoded['msg'].toString();
              break;
            }
          } catch (_) {
            if (line.isNotEmpty && !line.startsWith('{')) {
              errorDetail = line;
              break;
            }
          }
        }
        if (errorDetail.isEmpty && stderrList.isNotEmpty) {
          errorDetail = stderrList.last;
        }
        throw Exception(
          errorDetail.isNotEmpty
              ? 'iOS 投屏服务启动失败: $errorDetail'
              : (earlyExitCode != null
                  ? 'iOS 投屏服务异常退出 (退出码 $earlyExitCode)'
                  : 'iOS 投屏流端口响应超时'),
        );
      }

      // 注册新会话
      final session = IosMirrorSession(
        udid: udid,
        port: targetPort,
        process: process,
        startedAt: DateTime.now(),
      );
      _sessions[udid] = session;

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
