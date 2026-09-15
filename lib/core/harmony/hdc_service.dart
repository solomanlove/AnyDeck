import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../adb/adb_device.dart';
import '../adb/adb_result.dart';
import '../dal/device_driver.dart';
import '../dal/rust_dal_bridge.dart';
import '../process/tool_path_resolver.dart';

export 'hdc_service_device_info.dart';

/// HDC (HarmonyOS Device Connector) 服务封装，提供与纯血鸿蒙设备的通信指令。
class HdcService {
  HdcService({
    String? executable,
    void Function(String message, {String tag, String level})? onLog,
  })  : executable = executable ?? resolveToolPath('hdc'),
        _onLog = onLog;

  final String executable;
  final void Function(String message, {String tag, String level})? _onLog;

  final Map<String, String> _deviceModelCache = {};

  /// 获取已连接的鸿蒙设备列表。
  Future<List<AdbDevice>> listDevices() async {
    List<String> rawTargets = [];
    if (RustDalBridge.instance.isAvailable) {
      try {
        final targets = await RustDalBridge.instance.listHarmonyDevices();
        rawTargets = targets
            .where((item) {
              final status = (item['status'] as String? ?? '').toLowerCase();
              return status == 'connected' || (status.isNotEmpty && !status.contains('offline'));
            })
            .map((item) => item['serial'] as String? ?? '')
            .where((s) => s.isNotEmpty && !s.toLowerCase().contains('fail'))
            .toList();
      } catch (_) {}
    }

    if (rawTargets.isEmpty) {
      final vResult = await run(['list', 'targets', '-v']);
      if (vResult.isSuccess && vResult.stdout.isNotEmpty) {
        rawTargets = _parseRawTargetsWithStatus(vResult.stdout);
      }
      if (rawTargets.isEmpty) {
        final result = await run(['list', 'targets']);
        if (result.isSuccess) {
          rawTargets = _parseRawTargets(result.stdout);
        }
      }
    }
    if (rawTargets.isEmpty) return [];

    final devices = <AdbDevice>[];
    for (final id in rawTargets) {
      String modelName = _deviceModelCache[id] ?? '';
      if (modelName.isEmpty) {
        try {
          final paramRes = await shell(
            id,
            'param get const.product.name ; param get const.product.model ; param get const.product.marketing_name',
            timeout: const Duration(seconds: 2),
          );
          if (paramRes.isSuccess &&
              paramRes.stdout.isNotEmpty &&
              !paramRes.stdout.toLowerCase().contains('fail')) {
            final lines = const LineSplitter().convert(paramRes.stdout.trim());
            String name = '';
            String model = '';
            String marketingName = '';
            if (lines.isNotEmpty) name = lines[0].trim();
            if (lines.length > 1) model = lines[1].trim();
            if (lines.length > 2) marketingName = lines[2].trim();

            bool isValid(String s) =>
                s.isNotEmpty && !s.toLowerCase().contains('fail');

            if (isValid(marketingName)) {
              modelName = marketingName;
            } else if (isValid(name)) {
              modelName = name;
            } else if (isValid(model)) {
              modelName = model;
            }
          }
        } catch (_) {}

        if (modelName.isNotEmpty && !modelName.toLowerCase().contains('fail')) {
          _deviceModelCache[id] = modelName;
        }
      }

      devices.add(AdbDevice(
        id: id,
        status: 'device',
        model: modelName.isNotEmpty ? modelName : 'HarmonyOS Device',
        product: 'HarmonyOS NEXT',
        transportId: '',
        isHarmony: true,
      ));
    }
    return devices;
  }

  /// 封装的通用 hdc 命令执行。
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final cmdStr = 'hdc ${args.join(' ')}';
    _onLog?.call(cmdStr, tag: 'hdc', level: 'I');
    Process? process;
    try {
      process = await Process.start(executable, args);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(timeout);
      final result = AdbResult(
        exitCode: exitCode,
        stdout: await stdoutFuture,
        stderr: await stderrFuture,
      );
      if (!result.isSuccess && result.stderr.isNotEmpty) {
        _onLog?.call('Command failed: ${result.stderr.trim()}', tag: 'hdc', level: 'E');
      }
      return result;
    } on TimeoutException {
      process?.kill();
      await process?.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          return 124;
        },
      );
      final errorMsg = 'hdc 命令超时(${timeout.inSeconds}s): $cmdStr';
      _onLog?.call(errorMsg, tag: 'hdc', level: 'E');
      return AdbResult(
        exitCode: 124,
        stdout: '',
        stderr: errorMsg,
      );
    } on ProcessException catch (error) {
      _onLog?.call('Process error: ${error.message}', tag: 'hdc', level: 'E');
      return AdbResult(exitCode: 127, stdout: '', stderr: error.message);
    }
  }

  /// 在指定设备上执行单条 shell 命令 (优先走 Rust DAL 驱动，失败或未初始化时平滑降级走 CLI 通道)。
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (RustDalBridge.instance.isAvailable) {
      try {
        final out = await RustDalBridge.instance.executeShell(
          deviceId,
          command,
          platform: DevicePlatform.harmony,
        );
        return AdbResult(exitCode: 0, stdout: out, stderr: '');
      } catch (e) {
        // 原生驱动失败时平滑降级走下方通用 CLI 通道
      }
    }
    return run(['-t', deviceId, 'shell', command], timeout: timeout);
  }

  /// 注入 HarmonyOS 键盘事件；key code 必须使用 OpenHarmony 定义，不能直接复用 Android key code。
  Future<AdbResult> injectKey(String deviceId, int keyCode, {int repeat = 1}) {
    final safeRepeat = repeat.clamp(1, 30);
    final keyEvents = List<String>.filled(
      safeRepeat,
      '-d $keyCode -u $keyCode',
    ).join(' ');
    return shell(deviceId, 'uinput -K $keyEvents');
  }

  /// 向当前焦点输入框写入文本；新系统使用 uitest，旧系统对 ASCII 文本回退到 uinput。
  Future<AdbResult> inputText(String deviceId, String text) async {
    if (text.isEmpty) {
      return const AdbResult(exitCode: 1, stdout: '', stderr: '输入文本不能为空');
    }
    final escaped = text.replaceAll("'", "'\\''");
    final uiTestResult = await shell(
      deviceId,
      "uitest uiInput text '$escaped'",
    );
    if (uiTestResult.isSuccess || !RegExp(r'^[\x20-\x7E]+$').hasMatch(text)) {
      return uiTestResult;
    }
    return shell(deviceId, "uinput -K -t '$escaped'");
  }

  /// 切换 HarmonyOS 设备屏幕电源状态。
  Future<AdbResult> setScreenPower(String deviceId, {required bool powerOn}) {
    return shell(
      deviceId,
      powerOn ? 'power-shell wakeup' : 'power-shell suspend',
    );
  }

  /// 导出 HarmonyOS 当前窗口信息，供投屏工具栏查看前台窗口。
  Future<AdbResult> currentFocus(String deviceId) {
    return shell(deviceId, "hidumper -s WindowManagerService -a '-a'");
  }

  /// 截取鸿蒙手机屏幕截图，返回 PNG/JPEG 图像的原始字节。
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final remotePath = '/data/local/tmp/anydeck_screenshot_$timestamp.png';
    var snapRes = await shell(
      deviceId,
      'uitest screenCap -p $remotePath',
      timeout: timeout,
    );
    if (!snapRes.isSuccess) {
      snapRes = await shell(
        deviceId,
        'snapshot_display -f $remotePath',
        timeout: timeout,
      );
    }
    if (!snapRes.isSuccess) {
      throw Exception('HarmonyOS screenshot failed: ${snapRes.message}');
    }

    final tempDir = Directory.systemTemp;
    final localPath = '${tempDir.path}/anydeck_screenshot_$timestamp.png';

    final recvRes = await run([
      '-t',
      deviceId,
      'file',
      'recv',
      remotePath,
      localPath,
    ], timeout: timeout);
    final localFile = File(localPath);

    if (!recvRes.isSuccess || !await localFile.exists()) {
      unawaited(shell(deviceId, 'rm $remotePath'));
      throw Exception('HarmonyOS hdc file recv failed: ${recvRes.stderr}');
    }

    try {
      return await localFile.readAsBytes();
    } finally {
      unawaited(localFile.delete());
      unawaited(shell(deviceId, 'rm $remotePath'));
    }
  }

  /// 启动 HarmonyOS 系统录屏服务。
  Future<AdbResult> startScreenRecord(String deviceId, String fileName) {
    return shell(
      deviceId,
      'aa start -b com.huawei.hmos.screenrecorder '
      '-a com.huawei.hmos.screenrecorder.ServiceExtAbility '
      '--ps "CustomizedFileName" "$fileName"',
    );
  }

  /// 停止 HarmonyOS 系统录屏服务。
  Future<AdbResult> stopScreenRecord(String deviceId) {
    return shell(
      deviceId,
      'aa start -b com.huawei.hmos.screenrecorder '
      '-a com.huawei.hmos.screenrecorder.ServiceExtAbility',
    );
  }

  /// 查询系统录屏文件并下载到电脑。
  Future<void> receiveScreenRecord(
    String deviceId,
    String fileName,
    String localPath,
  ) async {
    final queryResult = await shell(deviceId, 'mediatool query "$fileName" -u');
    if (!queryResult.isSuccess) {
      throw Exception(
        'HarmonyOS mediatool query failed: ${queryResult.message}',
      );
    }

    var remotePath = _findMediaPath(queryResult.stdout, fileName);
    final mediaUri = RegExp(
      r'''file://[^\s"']+''',
    ).firstMatch(queryResult.stdout)?.group(0);
    if (mediaUri != null) {
      final exportPath = '/data/local/tmp/$fileName';
      final exportResult = await shell(
        deviceId,
        'mediatool recv "$mediaUri" $exportPath',
      );
      if (!exportResult.isSuccess) {
        throw Exception(
          'HarmonyOS mediatool recv failed: ${exportResult.message}',
        );
      }
      remotePath = _findMediaPath(exportResult.stdout, fileName) ?? exportPath;
    }
    if (remotePath == null) {
      throw Exception(
        'HarmonyOS recording path not found: ${queryResult.stdout}',
      );
    }

    final recvResult = await run([
      '-t',
      deviceId,
      'file',
      'recv',
      remotePath,
      localPath,
    ]);
    if (!recvResult.isSuccess) {
      throw Exception('HarmonyOS hdc file recv failed: ${recvResult.message}');
    }
    if (remotePath.startsWith('/data/local/tmp/')) {
      unawaited(shell(deviceId, 'rm $remotePath'));
    }
  }

  String? _findMediaPath(String output, String fileName) {
    final matches = RegExp(r'''(/[^\s"']+)''').allMatches(output);
    for (final match in matches) {
      final path = match.group(1);
      if (path != null && path.endsWith(fileName)) {
        return path;
      }
    }
    return null;
  }

  /// 启动 HDC 外部进程。
  Future<Process> start(List<String> args) {
    final cmdStr = 'hdc ${args.join(' ')}';
    _onLog?.call(cmdStr, tag: 'hdc', level: 'I');
    return Process.start(executable, args);
  }

  /// 向 HarmonyOS 设备推送文件或目录。
  Future<AdbResult> fileSend(
    String deviceId,
    String localPath,
    String remotePath, {
    Duration timeout = const Duration(minutes: 5),
  }) {
    return run([
      '-t',
      deviceId,
      'file',
      'send',
      localPath,
      remotePath,
    ], timeout: timeout);
  }

  /// 从 HarmonyOS 设备拉取文件或目录到本地。
  Future<AdbResult> fileRecv(
    String deviceId,
    String remotePath,
    String localPath, {
    Duration timeout = const Duration(minutes: 5),
  }) {
    return run([
      '-t',
      deviceId,
      'file',
      'recv',
      remotePath,
      localPath,
    ], timeout: timeout);
  }

  /// 启动拉取文件的进程，支持实时预览与取消。
  Future<Process> startFileRecv(
    String deviceId,
    String remotePath,
    String localPath,
  ) {
    return start(['-t', deviceId, 'file', 'recv', remotePath, localPath]);
  }

  /// 安装 HarmonyOS HAP/HSP 软件包。
  Future<AdbResult> installApp(
    String deviceId,
    String hapPath, {
    Duration timeout = const Duration(minutes: 5),
  }) {
    return run([
      '-t',
      deviceId,
      'app',
      'install',
      '-r',
      hapPath,
    ], timeout: timeout);
  }

  /// 递归删除 HarmonyOS 设备上的远程文件或目录。
  Future<AdbResult> delete(String deviceId, String remotePath) {
    final escaped = remotePath.replaceAll("'", "'\\''");
    return shell(deviceId, "rm -rf '$escaped'");
  }

  /// 在 HarmonyOS 设备上创建远程目录。
  Future<AdbResult> makeDirectory(String deviceId, String remotePath) {
    final escaped = remotePath.replaceAll("'", "'\\''");
    return shell(deviceId, "mkdir -p '$escaped'");
  }

  /// 解析 `hdc list targets -v` 输出，仅保留 Connected 且非 Offline 的在线设备。
  List<String> _parseRawTargetsWithStatus(String output) {
    final targets = <String>[];
    final lines = LineSplitter.split(output);
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.contains('[Empty]') ||
          trimmed.startsWith('[') ||
          trimmed.toLowerCase().contains('offline')) {
        continue;
      }
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        final serial = parts.first;
        final status = parts.length >= 3 ? parts[2].toLowerCase() : 'connected';
        if (status == 'connected' && !serial.toLowerCase().contains('fail')) {
          targets.add(serial);
        }
      }
    }
    return targets;
  }

  /// 开启鸿蒙设备的 TCP 监听模式 (默认 5555 端口)。
  Future<AdbResult> enableTcpMode(String deviceId, {int port = 5555}) {
    return run(['-t', deviceId, 'tmode', 'port', '$port']);
  }

  /// 通过无线网络连接到指定鸿蒙设备地址 (如 192.168.1.10:5555)。
  Future<AdbResult> connectWireless(String address) {
    return run(['tconn', address]);
  }

  /// 断开指定的鸿蒙无线设备连接。
  Future<AdbResult> disconnectWireless(String address) {
    return run(['tconn', address, '-remove']);
  }

  /// 查询鸿蒙设备的局域网 IPv4 地址。
  Future<String?> getDeviceIp(String deviceId) async {
    final res = await shell(deviceId, 'ifconfig wlan0');
    if (!res.isSuccess) return null;
    return parseIpFromIfconfig(res.stdout);
  }

  /// 从 `ifconfig wlan0` 输出中解析 IPv4 地址。
  static String? parseIpFromIfconfig(String output) {
    final match = RegExp(r'inet (?:addr:)?([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)').firstMatch(output);
    final ip = match?.group(1);
    if (ip == null || ip == '127.0.0.1') return null;
    return ip;
  }

  /// 解析 `hdc list targets` 输出的原始目标设备列表。
  List<String> _parseRawTargets(String output) {
    final targets = <String>[];
    final lines = LineSplitter.split(output);
    for (final line in lines) {
      final trimmed = line.trim();
      // 过滤空白行和异常提示行（例如 "[Empty]" 或包含 Fail 的错误输出）
      if (trimmed.isEmpty ||
          trimmed.contains('[Empty]') ||
          trimmed.startsWith('[') ||
          trimmed.toLowerCase().contains('fail') ||
          trimmed.contains(' ')) {
        continue;
      }
      targets.add(trimmed);
    }
    return targets;
  }
}
