/// HarmonyOS HDC 网络端点及连接状态模型。
class HarmonyWirelessEndpoint {
  const HarmonyWirelessEndpoint({
    required this.address,
    this.deviceSerial,
    this.lastConnectedAt,
  });

  final String address;
  final String? deviceSerial;
  final DateTime? lastConnectedAt;

  String get host => address.substring(0, address.lastIndexOf(':'));
  int get port => int.parse(address.substring(address.lastIndexOf(':') + 1));
}

/// HDC 网络端点校验，限定为 IPv4:Port，避免把用户输入透传为非预期 CLI 参数。
String? normalizeHarmonyEndpoint(String input) {
  final value = input.trim();
  final match = RegExp(
    r'^(\d{1,3}(?:\.\d{1,3}){3}):(\d{1,5})$',
  ).firstMatch(value);
  if (match == null) return null;
  final octets = match.group(1)!.split('.').map(int.tryParse).toList();
  final port = int.tryParse(match.group(2)!);
  if (octets.any((part) => part == null || part < 0 || part > 255) ||
      port == null ||
      port < 1 ||
      port > 65535) {
    return null;
  }
  return '${octets.join('.')}:$port';
}

class HarmonyWirelessState {
  const HarmonyWirelessState({
    this.history = const [],
    this.connectingAddress,
    this.autoReconnect = true,
    this.messageKey,
    this.error,
  });

  final List<HarmonyWirelessEndpoint> history;
  final String? connectingAddress;
  final bool autoReconnect;
  final String? messageKey;
  final String? error;

  HarmonyWirelessState copyWith({
    List<HarmonyWirelessEndpoint>? history,
    String? connectingAddress,
    bool clearConnectingAddress = false,
    bool? autoReconnect,
    String? messageKey,
    bool clearMessage = false,
    String? error,
    bool clearError = false,
  }) {
    return HarmonyWirelessState(
      history: history ?? this.history,
      connectingAddress: clearConnectingAddress
          ? null
          : connectingAddress ?? this.connectingAddress,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      messageKey: clearMessage ? null : messageKey ?? this.messageKey,
      error: clearError ? null : error ?? this.error,
    );
  }
}
