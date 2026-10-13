import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../process/tool_path_resolver.dart';
import 'adb_device.dart';
import 'adb_result.dart';

/// adb 薄封装，集中处理进程执行和设备列表解析。
class AdbService {
  AdbService({
    String? executable,
    void Function(String message, {String tag, String level})? onLog,
  })  : executable = executable ?? resolveToolPath('adb'),
        _onLog = onLog;

  static final RegExp _deviceLinePattern = RegExp(
    r'^(.*?)\s+(device|offline|unauthorized|recovery|sideload|bootloader|host|no permissions)(?:\s+(.*))?$',
  );

  final String executable;
  final void Function(String message, {String tag, String level})? _onLog;

  /// 启动需要由上层持有并主动取消的 adb 进程。
  Future<Process> start(List<String> args) {
    _onLog?.call('adb ${args.join(' ')}', tag: 'adb', level: 'I');
    return Process.start(executable, args);
  }

  /// 获取已连接设备列表；adb 不可用时抛出异常。
  Future<List<AdbDevice>> listDevices() async {
    final result = await run(['devices', '-l']);
    if (!result.isSuccess) {
      throw AdbException(result.message);
    }
    return _parseDevices(result.stdout);
  }

  /// 定时轮询 adb，仅在可见设备列表变化时发出新值。
  Stream<List<AdbDevice>> trackDevices({
    Duration interval = const Duration(seconds: 2),
  }) async* {
    yield await listDevices();
    yield* Stream.periodic(
      interval,
    ).asyncMap((_) => listDevices()).distinct(_sameDeviceList);
  }

  /// 使用原始参数执行 adb，并将进程异常转换为 AdbResult。
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final cmdStr = 'adb ${args.join(' ')}';
    _onLog?.call(cmdStr, tag: 'adb', level: 'I');
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
        _onLog?.call('Command failed: ${result.stderr.trim()}', tag: 'adb', level: 'E');
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
      final errorMsg = 'adb命令超时(${timeout.inSeconds}s): $cmdStr';
      _onLog?.call(errorMsg, tag: 'adb', level: 'E');
      return AdbResult(
        exitCode: 124,
        stdout: '',
        stderr: errorMsg,
      );
    } on ProcessException catch (error) {
      _onLog?.call('Process error: ${error.message}', tag: 'adb', level: 'E');
      return AdbResult(exitCode: 127, stdout: '', stderr: error.message);
    }
  }

  /// 终止并重新启动 ADB 服务端。
  Future<AdbResult> restartServer() async {
    final killResult = await run(['kill-server']);
    if (!killResult.isSuccess) {
      return killResult;
    }
    return run(['start-server']);
  }

  /// 在指定设备上执行单条 shell 命令字符串。
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    return run(['-s', deviceId, 'shell', command], timeout: timeout);
  }

  /// 在指定设备上执行 shell 参数列表，调用方无需手写 adb 前缀。
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    return run(['-s', deviceId, 'shell', ...args], timeout: timeout);
  }

  /// 解析 `adb devices -l` 返回的表格文本。
  List<AdbDevice> _parseDevices(String output) {
    return output
        .split('\n')
        .skip(1)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(_parseDeviceLine)
        .toList(growable: false);
  }

  /// 解析单行 adb 设备信息，并保留可选的 key:value 属性。
  AdbDevice? parseDeviceLine(String line) => _parseDeviceLine(line);

  AdbDevice _parseDeviceLine(String line) {
    final match = _deviceLinePattern.firstMatch(line);
    final id = match?.group(1) ?? line.split(RegExp(r'\s+')).first;
    final status = match?.group(2) ?? 'unknown';
    final attributesText = match?.group(3) ?? '';
    final parts = attributesText.split(RegExp(r'\s+'));
    final attributes = <String, String>{};

    for (final part in parts) {
      final separator = part.indexOf(':');
      if (separator > 0 && separator < part.length - 1) {
        attributes[part.substring(0, separator)] = part.substring(
          separator + 1,
        );
      }
    }

    return AdbDevice(
      id: id,
      status: status,
      model: attributes['model'],
      product: attributes['product'],
      transportId: attributes['transport_id'],
    );
  }

  /// 当 adb 连续返回相同列表时，避免 StreamProvider 重复刷新。
  /// 截取手机屏幕截图，返回 PNG 图像的原始字节。
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final cmdStr = 'adb -s $deviceId exec-out screencap -p';
    _onLog?.call(cmdStr, tag: 'adb', level: 'I');
    Process? process;
    try {
      process = await Process.start(executable, [
        '-s',
        deviceId,
        'exec-out',
        'screencap',
        '-p',
      ]);
      final stdoutFuture = process.stdout.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(timeout);
      final stderr = await stderrFuture;
      if (exitCode != 0) {
        final err = stderr.isNotEmpty
            ? stderr
            : 'Failed to capture screenshot (exit code $exitCode)';
        _onLog?.call('Screenshot failed: $err', tag: 'adb', level: 'E');
        throw AdbException(err);
      }
      final stdoutBytes = await stdoutFuture;
      return sanitizePngBytes(stdoutBytes, onLog: _onLog);
    } on TimeoutException {
      process?.kill();
      await process?.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          return 124;
        },
      );
      _onLog?.call('Screenshot command timeout', tag: 'adb', level: 'E');
      throw AdbException('adb截图命令超时(${timeout.inSeconds}s)');
    } on ProcessException catch (error) {
      _onLog?.call('Screenshot process error: ${error.message}', tag: 'adb', level: 'E');
      throw AdbException(error.message);
    }
  }

  /// 截取指定 Android Display，应用虚拟副屏直接使用其 logical displayId。
  Future<Uint8List> captureDisplayScreenshot(
    String deviceId,
    int displayId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final args = [
      '-s',
      deviceId,
      'exec-out',
      'screencap',
      '-d',
      '$displayId',
      '-p',
    ];
    _onLog?.call('adb ${args.join(' ')}', tag: 'adb', level: 'I');
    final process = await Process.start(executable, args);
    final stdoutFuture = process.stdout.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(timeout);
    final stderr = await stderrFuture;
    if (exitCode != 0) {
      throw AdbException(
        stderr.isNotEmpty
            ? stderr
            : 'Failed to capture display $displayId (exit code $exitCode)',
      );
    }
    final bytes = await stdoutFuture;
    if (bytes.isEmpty) {
      throw AdbException('Display $displayId screenshot returned empty data');
    }
    return Uint8List.fromList(bytes);
  }

  /// PNG 图像签名魔数 (89 50 4E 47 0D 0A 1A 0A)。
  static const List<int> _pngSignature = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  ];

  /// PNG 图像标准结束块 (00 00 00 00 49 45 4E 44 AE 42 60 82)。
  static const List<int> _pngIendChunk = [
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ];

  /// 在字节流中查找目标子序列的起始下标。
  static int _indexOfSublist(
    List<int> source,
    List<int> pattern, [
    int start = 0,
  ]) {
    if (pattern.isEmpty) return start;
    final maxSearch = source.length - pattern.length;
    for (var i = start; i <= maxSearch; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (source[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  /// 从字节流中安全提取纯净的 PNG 图片数据。
  /// 剔除 stdout 中可能混入的非图片前缀（如 Android 模拟器多显示屏时输出的 Warning 文本）与尾部垃圾数据。
  static Uint8List sanitizePngBytes(
    List<int> rawBytes, {
    void Function(String message, {String tag, String level})? onLog,
  }) {
    if (rawBytes.isEmpty) {
      throw const AdbException('未接收到截图数据');
    }

    // 1. 查找 PNG 图像签名起始位置
    final pngIndex = _indexOfSublist(rawBytes, _pngSignature);

    // 未找到 PNG 头，尝试作为文本解析错误提示
    if (pngIndex < 0) {
      final errorText = utf8.decode(rawBytes, allowMalformed: true).trim();
      if (errorText.isNotEmpty) {
        onLog?.call(
          'Screenshot returned non-image text: $errorText',
          tag: 'adb',
          level: 'E',
        );
        throw AdbException(errorText);
      }
      throw const AdbException('截图数据损坏或格式不受支持');
    }

    // 若前面混入了非图片内容（如模拟器多屏幕 Warning），丢弃前缀并打日志
    if (pngIndex > 0) {
      final prefixText = utf8.decode(
        rawBytes.sublist(0, pngIndex),
        allowMalformed: true,
      ).trim();
      onLog?.call(
        'Screenshot stdout contained warning/text prefix ($pngIndex bytes): $prefixText',
        tag: 'adb',
        level: 'W',
      );
    }

    var validBytes = rawBytes.sublist(pngIndex);

    // 2. 检查是否有多余的尾部脏数据（以 PNG 标准 IEND 块为准截断）
    final iendIndex = _indexOfSublist(validBytes, _pngIendChunk);
    if (iendIndex >= 0) {
      final expectedEnd = iendIndex + _pngIendChunk.length;
      if (expectedEnd < validBytes.length) {
        final trailingBytes = validBytes.length - expectedEnd;
        onLog?.call(
          'Screenshot stdout contained trailing data ($trailingBytes bytes), trimmed',
          tag: 'adb',
          level: 'W',
        );
        validBytes = validBytes.sublist(0, expectedEnd);
      }
    }

    return Uint8List.fromList(validBytes);
  }

  /// 开始录制手机屏幕，返回 Process 实例。
  Future<Process> startScreenRecord(
    String deviceId,
    String remotePath, {
    int timeLimit = 180,
    int? bitRate,
    String? size,
  }) {
    final args = <String>[
      '-s',
      deviceId,
      'shell',
      'screenrecord',
      '--time-limit',
      '$timeLimit',
    ];
    if (bitRate != null) {
      args.addAll(['--bit-rate', '$bitRate']);
    }
    if (size != null) {
      args.addAll(['--size', size]);
    }
    args.add(remotePath);
    _onLog?.call('adb ${args.join(' ')}', tag: 'adb', level: 'I');
    return Process.start(executable, args);
  }

  /// 录制指定 Android Display；调用方负责停止进程并拉取 remotePath。
  Future<Process> startDisplayScreenRecord(
    String deviceId,
    String remotePath,
    int displayId, {
    int timeLimit = 180,
  }) {
    final args = <String>[
      '-s',
      deviceId,
      'shell',
      'screenrecord',
      '--display-id',
      '$displayId',
      '--time-limit',
      '$timeLimit',
      remotePath,
    ];
    _onLog?.call('adb ${args.join(' ')}', tag: 'adb', level: 'I');
    return Process.start(executable, args);
  }

  /// 检查设备是否支持 screenrecord 命令
  Future<bool> isScreenRecordSupported(String deviceId) async {
    final result = await shell(deviceId, 'which screenrecord');
    return result.isSuccess && result.stdout.trim().isNotEmpty;
  }

  /// 停止录屏（通过发送 SIGINT 信号使 screenrecord 正常保存文件）。
  Future<AdbResult> stopScreenRecord(String deviceId) {
    return shell(
      deviceId,
      'pkill -2 -f screenrecord || pkill -2 screenrecord || killall -2 screenrecord || (pid=\$(pidof screenrecord) && [ -n "\$pid" ] && kill -2 \$pid)',
    );
  }

  bool _sameDeviceList(List<AdbDevice> previous, List<AdbDevice> next) {
    if (previous.length != next.length) {
      return false;
    }
    for (var index = 0; index < previous.length; index += 1) {
      final left = previous[index];
      final right = next[index];
      if (left.id != right.id ||
          left.status != right.status ||
          left.model != right.model ||
          left.product != right.product) {
        return false;
      }
    }
    return true;
  }
}

/// adb 无法返回有效设备列表时使用的异常。
class AdbException implements Exception {
  const AdbException(this.message);

  final String message;

  @override
  String toString() => message;
}
