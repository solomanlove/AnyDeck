/// IPC 与记录中的传输协议白名单；旧事件/旧记录缺少字段时沿用 Huawei。
enum ShareTransferProtocol {
  huawei,
  honor;

  /// 只接受明确的协议名称，不能由端口、设备名或品牌字符串猜测。
  static ShareTransferProtocol parse(Object? value) => switch (value) {
    'huawei' => huawei,
    'honor' => honor,
    _ => throw const FormatException('Invalid Share Core protocol'),
  };

  static ShareTransferProtocol fromMap(Map<String, dynamic> value) =>
      value.containsKey('protocol') ? parse(value['protocol']) : huawei;

  /// 保留旧 Huawei 地址key，Honor单独命名，避免同IP覆盖或跨协议重试。
  String peerKey(String address) => this == huawei ? address : 'honor:$address';
}
