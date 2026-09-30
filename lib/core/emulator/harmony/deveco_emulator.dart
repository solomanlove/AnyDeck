/// 华为 HarmonyOS DevEco 模拟器数据模型。
class DevEcoEmulator {
  /// 创建 DevEco 模拟器实体。
  const DevEcoEmulator({
    required this.name,
    required this.apiVersion,
    required this.deviceType,
    required this.state,
    this.id,
    this.configPath,
    this.resolution,
  });

  /// 模拟器唯一标识或端口
  final String? id;

  /// 模拟器显示名称（如 Phone-API12）
  final String name;

  /// OpenHarmony / HarmonyOS API 级别（如 API 12 / NEXT）
  final String apiVersion;

  /// 设备形态（Phone / Tablet / 2in1 / Wearable）
  final String deviceType;

  /// 当前状态（"Running"、"Stopped" 等）
  final String state;

  /// 配置文件存放路径
  final String? configPath;

  /// 分辨率
  final String? resolution;

  /// 是否处于运行中状态
  bool get isRunning => state.toLowerCase() == 'running';
}
