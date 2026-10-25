import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import '../harmony/hdc_service.dart';

/// 端口转发命令的平台适配层。
///
/// 反向转发使用 `adb reverse` / `hdc rport`；正向转发使用
/// `adb forward` / `hdc fport`，UI 与 Provider 统一通过本类执行。
class PortForwardCommand {
  PortForwardCommand._();

  /// 查询宿主机端口到设备端口的正向 TCP 映射。
  static Future<AdbResult> listForward(
    AdbService adb,
    HdcService? hdc, {
    required String deviceId,
    required bool isHarmony,
  }) {
    if (isHarmony) {
      return hdc == null
          ? Future.value(_missingHdc())
          : hdc.listForwardRules(deviceId);
    }
    return adb.run(['-s', deviceId, 'forward', '--list']);
  }

  /// 建立正向 TCP 映射：电脑 localhost:[localPort] → 设备 localhost:[devicePort]。
  static Future<AdbResult> addForward(
    AdbService adb,
    HdcService? hdc, {
    required String deviceId,
    required bool isHarmony,
    required int localPort,
    required int devicePort,
  }) {
    if (!_validPort(localPort) || !_validPort(devicePort)) {
      return Future.value(_invalidPort());
    }
    if (isHarmony) {
      return hdc == null
          ? Future.value(_missingHdc())
          : hdc.forward(deviceId, localPort, 'tcp:$devicePort');
    }
    return adb.run([
      '-s',
      deviceId,
      'forward',
      'tcp:$localPort',
      'tcp:$devicePort',
    ]);
  }

  /// 删除指定正向映射；HDC 必须同时提供两端端口。
  static Future<AdbResult> removeForward(
    AdbService adb,
    HdcService? hdc, {
    required String deviceId,
    required bool isHarmony,
    required int localPort,
    required int devicePort,
  }) {
    if (!_validPort(localPort) || !_validPort(devicePort)) {
      return Future.value(_invalidPort());
    }
    if (isHarmony) {
      return hdc == null
          ? Future.value(_missingHdc())
          : hdc.removeForward(deviceId, localPort, 'tcp:$devicePort');
    }
    return adb.run(['-s', deviceId, 'forward', '--remove', 'tcp:$localPort']);
  }

  static bool _validPort(int port) => port >= 1 && port <= 65535;

  static AdbResult _invalidPort() =>
      AdbResult(exitCode: 1, stdout: '', stderr: '端口必须在 1-65535 之间');

  static AdbResult _missingHdc() =>
      AdbResult(exitCode: 127, stdout: '', stderr: 'HdcService 未注入，无法执行鸿蒙端口转发');

  /// 执行"设备端口 -> 本地端口"的反向转发命令。
  ///
  /// [reverseArgs] 与 adb reverse 参数一致：
  /// - `--list`：列出当前转发
  /// - `--remove tcp:<port>`：删除一条转发
  /// - `tcp:<devicePort> tcp:<localPort>`：建立转发
  static Future<AdbResult> run(
    AdbService adb,
    HdcService? hdc, {
    required String deviceId,
    required bool isHarmony,
    required List<String> reverseArgs,
  }) async {
    if (isHarmony) {
      if (hdc == null) {
        return AdbResult(
          exitCode: 127,
          stdout: '',
          stderr: 'HdcService 未注入，无法执行鸿蒙端口转发',
        );
      }
      return _runHdc(hdc, deviceId, reverseArgs);
    }
    return adb.run(['-s', deviceId, 'reverse', ...reverseArgs]);
  }

  /// 鸿蒙分支：将 adb reverse 语法映射为 hdc 命令。
  ///
  /// 实测鸿蒙 `hdc rport` 仅支持创建，列表与删除均需走 `fport`，
  /// 删除时必须同时给出设备端口与本地端口双节点。
  static Future<AdbResult> _runHdc(
    HdcService hdc,
    String deviceId,
    List<String> args,
  ) async {
    if (args.length == 1 && args[0] == '--list') {
      return hdc.listReverseForwards(deviceId);
    }
    if (args.length >= 2 && args[0] == '--remove') {
      final port = _parsePort(args[1]);
      if (port == null) {
        return AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '无效端口: ${args[1]}',
        );
      }
      if (args.length < 3 ||
          (!args[2].startsWith('tcp:') &&
              !args[2].startsWith('localabstract:'))) {
        return AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '鸿蒙删除反向转发需要设备端口与本地端口双子节点，如: '
              '--remove tcp:8788 tcp:8788',
        );
      }
      return hdc.removeReverseForward(deviceId, port, args[2]);
    }
    if (args.length == 2) {
      final devicePort = _parsePort(args[0]);
      if (devicePort == null) {
        return AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '无效端口: ${args[0]}',
        );
      }
      return hdc.reverseForward(deviceId, devicePort, args[1]);
    }
    return AdbResult(exitCode: 1, stdout: '', stderr: '不支持的参数: $args');
  }

  /// 解析 `tcp:8081` 或裸端口字符串为端口号。
  static int? _parsePort(String value) {
    final normalized = value.startsWith('tcp:') ? value.substring(4) : value;
    return int.tryParse(normalized);
  }
}