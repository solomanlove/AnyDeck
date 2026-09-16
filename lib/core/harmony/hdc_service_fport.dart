import '../adb/adb_result.dart';
import 'hdc_service.dart';

/// HDC 端口转发扩展，封装 `hdc fport`（正向转发）与 `hdc rport`（反向转发）。
///
/// 鸿蒙的转发语法与 adb 类似：`hdc fport tcp:<local> localabstract:<remote>`；
/// 查询为 `hdc fport ls`，删除为 `hdc fport rm tcp:<local> <remote>`。
/// 注意：`fport rm` 必须同时给出 local 与 remote 两个节点，仅传 `tcp:<port>`
/// 会被 daemon 判为 "ruler is not exist" 而删除失败。
extension HdcServiceFport on HdcService {
  /// 建立正向端口转发：宿主机 [localPort] -> 设备侧 [remoteSpec]。
  ///
  /// [remoteSpec] 例如 `localabstract:webview_devtools_remote_1234` 或 `tcp:8080`。
  Future<AdbResult> forward(
    String deviceId,
    int localPort,
    String remoteSpec,
  ) {
    return run(['-t', deviceId, 'fport', 'tcp:$localPort', remoteSpec]);
  }

  /// 删除一条正向端口转发规则。
  ///
  /// 优先使用 [remoteSpec] 发送 `fport rm tcp:<port> <remoteSpec>`（daemon 要求
  /// 双参数）；若调用方无法提供 remoteSpec 则退化为单参数，删除可能失败但不抛
  /// 异常，残留规则会在后续 scanTargets 的 _removeStaleForwards 中被清理。
  Future<AdbResult> removeForward(
    String deviceId,
    int localPort, [
    String? remoteSpec,
  ]) {
    final args = [
      '-t',
      deviceId,
      'fport',
      'rm',
      'tcp:$localPort',
    ];
    if (remoteSpec != null && remoteSpec.isNotEmpty) {
      args.add(remoteSpec);
    }
    return run(args);
  }

  /// 列出当前设备的所有端口转发规则。
  ///
  /// 输出形如 `[tcp:1234 localabstract:xxx]`，调用方自行解析。
  Future<AdbResult> listForwards(String deviceId) {
    return run(['-t', deviceId, 'fport', 'ls']);
  }

  /// 建立反向端口转发：设备侧 [remotePort] -> 宿主机 [localSpec]。
  ///
  /// [localSpec] 例如 `tcp:8080`。
  Future<AdbResult> reverseForward(
    String deviceId,
    int remotePort,
    String localSpec,
  ) {
    return run(['-t', deviceId, 'rport', 'tcp:$remotePort', localSpec]);
  }

  /// 删除一条反向端口转发规则。
  Future<AdbResult> removeReverseForward(String deviceId, int remotePort) {
    return run(['-t', deviceId, 'rport', 'rm', 'tcp:$remotePort']);
  }

  /// 列出当前设备的所有反向端口转发规则。
  ///
  /// 输出形如 `[tcp:8100 tcp:8080]`，调用方自行解析。
  Future<AdbResult> listReverseForwards(String deviceId) {
    return run(['-t', deviceId, 'rport', 'ls']);
  }
}