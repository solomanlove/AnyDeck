import 'dart:convert';

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
  /// 输出中正向转发行形如 `tcp:1234 localabstract:xxx [Forward]`，
  /// 反向转发行形如 `tcp:8788 tcp:8788 [Reverse]`，调用方自行解析。
  Future<AdbResult> listForwards(String deviceId) {
    return run(['-t', deviceId, 'fport', 'ls']);
  }

  /// 仅保留 `fport ls` 中的正向规则，避免把反向映射显示为正向。
  Future<AdbResult> listForwardRules(String deviceId) async {
    final result = await listForwards(deviceId);
    if (!result.isSuccess) return result;
    return AdbResult(
      exitCode: result.exitCode,
      stdout: result.stdout
          .split('\n')
          .where((line) => line.contains('[Forward]'))
          .join('\n'),
      stderr: result.stderr,
    );
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
  ///
  /// 实测鸿蒙 `hdc rport` 仅支持创建子命令，删除需要通过 `fport rm` 完成，
  /// 且 daemon 要求同时给出设备端口与本地端口两个节点，单参数会被判为
  /// "Incorrect forward command" 而删除失败。
  Future<AdbResult> removeReverseForward(
    String deviceId,
    int remotePort,
    String localSpec,
  ) {
    return run([
      '-t',
      deviceId,
      'fport',
      'rm',
      'tcp:$remotePort',
      localSpec,
    ]);
  }

  /// 列出当前设备的所有反向端口转发规则。
  ///
  /// 实测鸿蒙 `hdc rport ls` 不存在（返回 `[Fail]Incorrect forward command`），
  /// 反向转发出现在 `hdc fport ls` 中并以 `[Reverse]` 标注（正向为 `[Forward]`）。
  /// 因此改走 `fport ls` 并过滤出 `[Reverse]` 条目，返回的 stdout 形如
  /// `tcp:8100 tcp:8080`，由调用方自行解析。
  Future<AdbResult> listReverseForwards(String deviceId) async {
    final result = await run(['-t', deviceId, 'fport', 'ls']);
    if (!result.isSuccess) {
      return result;
    }
    return AdbResult(
      exitCode: result.exitCode,
      stdout: filterReverseOnly(result.stdout),
      stderr: result.stderr,
    );
  }

  /// 从 `hdc fport ls` 输出中仅保留反向转发条目。
  ///
  /// 输出中反向转发行以 `[Reverse]` 结尾，如 `tcp:8788 tcp:8788 [Reverse]`；
  /// 正向转发行（即使两端都是 tcp）以 `[Forward]` 结尾，必须在此过滤，
  /// 否则后续解析时正向与反向难以区分。同时剥离行首设备序列号前缀，
  /// 仅保留 `节点A 节点B` 形式的转发规则，便于统一解析。
  static String filterReverseOnly(String stdout) {
    final rulePattern = RegExp(r'(tcp:\d+\s+\S+)');
    return LineSplitter
        .split(stdout)
        .where((line) => line.contains('[Reverse]'))
        .map((line) => rulePattern.firstMatch(line)?.group(1) ?? '')
        .where((line) => line.isNotEmpty)
        .join('\n');
  }
}