/// 分享方监听结束的受控原因；日志中不接受设备数据或分享凭据作为原因。
enum HostedShareStopReason {
  requested,
  expired,
  sourceUnavailable,
  sourceTransportChanged,
  reconfigured,
  ruleRemoved,
  setupFailed,
  appExit,
  listenerError,
}

/// 诊断回调不能干扰共享清理；调用方只传固定事件、方向和异常类型。
void reportDeviceShareDiagnostic(void Function(String)? report, String event) {
  try {
    report?.call(event);
  } catch (_) {
    // 日志存储或观察者失效时，仍必须关闭原会话并释放 Socket。
  }
}
