import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../adb/adb_device.dart';
import '../adb/adb_result.dart';
import '../process/tool_path_resolver.dart';

/// HDC (HarmonyOS Device Connector) 服务封装，提供与纯血鸿蒙设备的通信指令。
class HdcService {
  HdcService({
    String? executable,
    void Function(String message, {String tag, String level})? onLog,
  })  : executable = executable ?? resolveToolPath('hdc'),
        _onLog = onLog;

  final String executable;
  final void Function(String message, {String tag, String level})? _onLog;

  /// 获取已连接的鸿蒙设备列表。
  Future<List<AdbDevice>> listDevices() async {
    final result = await run(['list', 'targets']);
    if (!result.isSuccess) {
      return [];
    }
    return _parseDevices(result.stdout);
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

  /// 在指定设备上执行单条 shell 命令。
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) {
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

  /// 解析 `hdc list targets` 输出的设备列表。
  List<AdbDevice> _parseDevices(String output) {
    final devices = <AdbDevice>[];
    final lines = LineSplitter.split(output);
    for (final line in lines) {
      final trimmed = line.trim();
      // 过滤空白行和异常提示行（例如 "[Empty]" 或错误输出）
      if (trimmed.isEmpty || trimmed.contains('[Empty]') || trimmed.startsWith('[') || trimmed.contains(' ')) {
        continue;
      }
      // 鸿蒙 NEXT 的 hdc 默认直接输出设备的 UDID/ID
      devices.add(AdbDevice(
        id: trimmed,
        status: 'device',
        model: 'HarmonyOS NEXT Device ($trimmed)',
        product: 'HarmonyOS NEXT',
        transportId: '',
        isHarmony: true,
      ));
    }
    return devices;
  }
}
