import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../adb/adb_device.dart';
import '../../adb/wireless/adb_wireless_state.dart';
import '../../harmony/hdc_service.dart';
import 'device_registry_providers.dart';

/// 设备注册表中的统一设备模型。
///
/// 汇总了 ADB、HDC（鸿蒙）及 iOS 设备的物理属性、网络连接、版本信息及用户自定义备注。
class RegisteredDevice {
  const RegisteredDevice({
    required this.id,
    this.customName,
    required this.status,
    this.model,
    this.product,
    this.transportId,
    required this.isOnline,
    this.isChecked = false,
    this.connections = const [],
    this.serial,
    this.ipAddress,
    this.androidVersion,
    this.sdkVersion,
    this.isIos = false,
    this.isHarmony = false,
    this.remark,
    this.tags = const [],
  });

  /// 设备通信唯一标识符（如序列号、IP:端口、UDID 或 HDC ID）
  final String id;

  /// 用户自定义的别名
  final String? customName;

  /// 设备连接状态（如 'device', 'offline', 'unauthorized' 等）
  final String status;

  /// 设备型号名称（如 Pixel 7, Pura 70 等）
  final String? model;

  /// 产品代号（如 flame, HarmonyOS NEXT 等）
  final String? product;

  /// ADB transport ID
  final String? transportId;

  /// 设备当前是否处于在线可通信状态
  final bool isOnline;

  /// 在多设备管理列表中是否被复选框选中
  final bool isChecked;

  /// 归属于该硬件设备的所有活跃或历史连接通道 ID 列表（例如包含 USB 序列号和 Wi-Fi IP:Port）
  final List<String> connections;

  /// 设备的真实物理硬件序列号
  final String? serial;

  /// 设备的 Wi-Fi 局域网 IP 地址
  final String? ipAddress;

  /// 系统版本描述字符串，例如 "Android 14 (API 34)" 或 "HarmonyOS NEXT (API 23)"
  final String? androidVersion;

  /// 系统 API SDK 级别整数
  final int? sdkVersion;

  /// 是否为 iOS 设备
  final bool isIos;

  /// 是否为鸿蒙（HarmonyOS NEXT / OpenHarmony）设备
  final bool isHarmony;

  /// 用户对该设备的自定义备注信息
  final String? remark;

  /// 用户为该设备标记的分类标签列表
  final List<String> tags;

  /// 判断该连接是否为网络（Wi-Fi/以太网）连接
  bool get isNetwork =>
      id.contains(':') || id.contains('.') || id == '127.0.0.1';

  /// 从连接标识符中解析网络端口号（若为纯 IP 则默认 5555，非网络连接返回 null）
  static int? parseConnectionPort(String connectionId) {
    if (connectionId.contains('_adb-tls-connect._tcp')) return null;
    if (!connectionId.contains(':')) {
      if (connectionId.contains('.')) return 5555;
      return null;
    }
    final parts = connectionId.split(':');
    if (parts.length >= 2) {
      return int.tryParse(parts.last);
    }
    return null;
  }

  /// 设备当前是否包含物理 USB 连接
  bool get hasUsbConnection {
    if (connections.isEmpty) return !isNetwork;
    return connections.any(
      (c) => !(c.contains(':') || c.contains('.') || c == '127.0.0.1'),
    );
  }

  /// 设备当前是否包含 TCP/IP 连接（传统网络调试，默认 5555 端口）
  bool get hasTcpConnection {
    if (connections.isEmpty) {
      if (!isNetwork) return false;
      final port = parseConnectionPort(id);
      return !isWirelessTlsId(id) && (port == 5555 || port == null);
    }
    return connections.any((c) {
      if (!c.contains(':') && !c.contains('.')) return false;
      final port = parseConnectionPort(c);
      return !isWirelessTlsId(c) && (port == 5555 || port == null);
    });
  }

  /// 设备当前是否包含 WiFi 无线调试连接（Android 11+ 配对或非 5555 动态高位端口）
  bool get hasWifiDebuggingConnection {
    if (connections.isEmpty) {
      if (!isNetwork) return false;
      return isWirelessTlsId(id);
    }
    return connections.any((c) {
      if (!c.contains(':') && !c.contains('.')) return false;
      return isWirelessTlsId(c);
    });
  }

  /// 获取执行命令与数据传输的最佳优先 ID：
  /// 若多种方式同时连接，严格保证优先使用 USB 连接
  String get preferredCommandId {
    if (connections.isEmpty) return id;
    final usbId = connections.firstWhere(
      (c) => !(c.contains(':') || c.contains('.') || c == '127.0.0.1'),
      orElse: () => '',
    );
    if (usbId.isNotEmpty) return usbId;
    final tcpId = connections.firstWhere(
      (c) => !isWirelessTlsId(c) &&
          (parseConnectionPort(c) == 5555 || c.contains('._adb._tcp')),
      orElse: () => '',
    );
    if (tcpId.isNotEmpty) return tcpId;
    return id;
  }

  /// 获取设备的局域网 Wi-Fi IP 地址
  String? get wifiIp {
    if (ipAddress != null && ipAddress!.isNotEmpty && ipAddress != '-') {
      final ip = wirelessIpv4(ipAddress);
      if (ip != null) return ip;
    }
    if (isNetwork) {
      final parts = id.split(':');
      if (parts.isNotEmpty) {
        return wirelessIpv4(parts.first);
      }
    }
    return null;
  }

  /// UI 展示名称（优先展示自定义别名，其次展示设备型号，最后回退为 ID）
  String get displayName {
    if (customName != null && customName!.isNotEmpty) {
      return customName!;
    }
    if (model != null &&
        model!.isNotEmpty &&
        !HdcServiceDeviceInfo.isGenericOrInvalidModel(model)) {
      return model!.replaceAll('_', ' ');
    }
    return id;
  }

  /// 连接方式及型号的详细展示文本（例如 "Pixel 7 (9A123BC)"）
  String get connectionMethodDisplay {
    final hasValidModel = model != null &&
        model!.isNotEmpty &&
        !HdcServiceDeviceInfo.isGenericOrInvalidModel(model);
    final name = hasValidModel ? model!.replaceAll('_', ' ') : id;
    // 鸿蒙设备 serial 与 id 相同（HDC Device ID），不重复追加
    if (serial != null &&
        serial!.isNotEmpty &&
        serial != id &&
        !HdcServiceDeviceInfo.isGenericOrInvalidModel(serial)) {
      return '$name($serial)';
    }
    return name;
  }

  /// 转换为轻量级的 AdbDevice 对象，供底层命令服务使用
  AdbDevice get toAdbDevice => AdbDevice(
    id: id,
    status: status,
    model: model,
    product: product,
    transportId: transportId,
    isIos: isIos,
    isHarmony: isHarmony,
  );

  /// 复制并更新部分属性
  RegisteredDevice copyWith({
    String? id,
    String? customName,
    String? status,
    String? model,
    String? product,
    String? transportId,
    bool? isOnline,
    bool? isChecked,
    List<String>? connections,
    String? serial,
    String? ipAddress,
    String? androidVersion,
    int? sdkVersion,
    bool? isIos,
    bool? isHarmony,
    String? remark,
    List<String>? tags,
  }) {
    return RegisteredDevice(
      id: id ?? this.id,
      customName: customName ?? this.customName,
      status: status ?? this.status,
      model: model ?? this.model,
      product: product ?? this.product,
      transportId: transportId ?? this.transportId,
      isOnline: isOnline ?? this.isOnline,
      isChecked: isChecked ?? this.isChecked,
      connections: connections ?? this.connections,
      serial: serial ?? this.serial,
      ipAddress: ipAddress ?? this.ipAddress,
      androidVersion: androidVersion ?? this.androidVersion,
      sdkVersion: sdkVersion ?? this.sdkVersion,
      isIos: isIos ?? this.isIos,
      isHarmony: isHarmony ?? this.isHarmony,
      remark: remark ?? this.remark,
      tags: tags ?? this.tags,
    );
  }
}

/// 全局设备 Android/系统版本字符串 Provider，格式如 `Android 10 (API 29)`。
///
/// 入参 [deviceId] 为设备 ID。
final deviceAndroidVersionProvider = Provider.autoDispose
    .family<String?, String>((ref, deviceId) {
      final devices = ref.watch(deviceRegistryProvider);
      for (final device in devices) {
        if (device.id == deviceId ||
            device.serial == deviceId ||
            device.connections.contains(deviceId)) {
          return device.androidVersion;
        }
      }
      return null;
    });

/// 全局设备 SDK 版本号 Provider，供投屏、备份、音量等逻辑直接判断系统能力。
///
/// 入参 [deviceId] 为设备 ID。
final deviceSdkVersionProvider = Provider.autoDispose.family<int?, String>((
  ref,
  deviceId,
) {
  final devices = ref.watch(deviceRegistryProvider);
  for (final device in devices) {
    if (device.id == deviceId ||
        device.serial == deviceId ||
        device.connections.contains(deviceId)) {
      return device.sdkVersion;
    }
  }
  return null;
});
