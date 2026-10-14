import '../ios/ios_connection_type.dart';

/// `adb devices -l` 输出中的一行设备信息。
class AdbDevice {
  const AdbDevice({
    required this.id,
    required this.status,
    this.model,
    this.product,
    this.transportId,
    this.isIos = false,
    this.isHarmony = false,
    this.iosConnectionTypes = const {},
  });

  final String id;
  final String status;
  final String? model;
  final String? product;
  final String? transportId;
  final bool isIos;
  final bool isHarmony;

  /// iOS 使用 UDID 路由，连接方式须保留发现结果，支持 USB 与网络同时在线。
  final Set<IosConnectionType> iosConnectionTypes;

  /// 判断设备发现结果是否包含可用于命令路由和持久化的真实设备 ID。
  static bool hasUsableId(String value) {
    final id = value.trim();
    if (id.isEmpty) return false;
    final normalized = id.toLowerCase();
    if (normalized == '-' ||
        normalized == 'unknown' ||
        normalized == 'no serial number' ||
        normalized == '(no serial number)') {
      return false;
    }
    return !RegExp(r'^\?+$').hasMatch(id);
  }

  /// adb 状态为 device 时，才表示设备可执行 shell 命令。
  bool get isOnline => status == 'device';

  /// 展示给用户的设备名，优先使用 adb 返回的 model。
  String get displayName {
    if (model != null && model!.isNotEmpty) {
      return model!.replaceAll('_', ' ');
    }
    return id;
  }
}
