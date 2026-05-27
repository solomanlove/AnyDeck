/// `adb devices -l` 输出中的一行设备信息。
class AdbDevice {
  const AdbDevice({
    required this.id,
    required this.status,
    this.model,
    this.product,
    this.transportId,
  });

  final String id;
  final String status;
  final String? model;
  final String? product;
  final String? transportId;

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
