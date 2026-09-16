import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import '../harmony/hdc_service.dart';

/// 端口转发命令的平台适配层。
///
/// 安卓使用 `adb reverse`（设备端口 -> 本地端口）；鸿蒙使用 `hdc rport`
/// （设备侧监听并转发到宿主机），两者语义一致，仅命令通道不同。
/// 收口各处散落的 adb 调用，UI 与 Provider 统一通过 [run] 执行。
class PortForwardCommand {
  PortForwardCommand._();

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

  /// 鸿蒙分支：将 adb reverse 语法映射为 hdc rport。
  static Future<AdbResult> _runHdc(
    HdcService hdc,
    String deviceId,
    List<String> args,
  ) async {
    if (args.length == 1 && args[0] == '--list') {
      return hdc.listReverseForwards(deviceId);
    }
    if (args.length == 2 && args[0] == '--remove') {
      final port = _parsePort(args[1]);
      if (port == null) {
        return AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '无效端口: ${args[1]}',
        );
      }
      return hdc.removeReverseForward(deviceId, port);
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