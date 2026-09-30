/// iOS 模拟器数据模型。
class IosSimulator {
  /// 创建 iOS 模拟器数据实体。
  const IosSimulator({
    required this.udid,
    required this.name,
    required this.runtime,
    required this.deviceTypeIdentifier,
    required this.state,
    required this.isAvailable,
    this.dataPath,
    this.logPath,
    this.dataPathSize,
    this.lastBootedAt,
  });

  /// 模拟器唯一标识 UUID
  final String udid;

  /// 模拟器名称（如 iPhone 17 Pro）
  final String name;

  /// iOS 系统运行时标签（如 iOS 26.3）
  final String runtime;

  /// 设备机型标识
  final String deviceTypeIdentifier;

  /// 当前状态（"Booted"、"Shutdown" 等）
  final String state;

  /// 是否可用
  final bool isAvailable;

  /// 数据存放目录绝对路径
  final String? dataPath;

  /// 日志存放目录绝对路径
  final String? logPath;

  /// 数据目录占用字节大小
  final int? dataPathSize;

  /// 上次启动时间
  final DateTime? lastBootedAt;

  /// 模拟器是否处于正在运行状态
  bool get isBooted => state.toLowerCase() == 'booted';

  /// 友好格式化磁盘数据大小
  String get displayDataSize {
    if (dataPathSize == null || dataPathSize! <= 0) return '-';
    final bytes = dataPathSize!;
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 从 `xcrun simctl list --json devices available` 解析实体
  factory IosSimulator.fromJson(Map<String, dynamic> json, {String runtime = ''}) {
    DateTime? bootedTime;
    if (json['lastBootedAt'] != null) {
      bootedTime = DateTime.tryParse(json['lastBootedAt'].toString());
    }
    return IosSimulator(
      udid: json['udid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      runtime: runtime,
      deviceTypeIdentifier: json['deviceTypeIdentifier'] as String? ?? '',
      state: json['state'] as String? ?? 'Shutdown',
      isAvailable: json['isAvailable'] as bool? ?? true,
      dataPath: json['dataPath'] as String?,
      logPath: json['logPath'] as String?,
      dataPathSize: (json['dataPathSize'] as num?)?.toInt(),
      lastBootedAt: bootedTime,
    );
  }
}
