import 'dart:io';

import '../emulator/emulator_connection.dart';
import '../providers/modules/registered_device_model.dart';

/// 平台分类与设备身份共用的命名空间，避免不同协议相同 ID 串组。
enum DeviceGroupPlatform {
  android,
  harmony,
  ios;

  static DeviceGroupPlatform of(RegisteredDevice device) => device.isIos
      ? ios
      : device.isHarmony
      ? harmony
      : android;
}

/// 自定义组成员的物理身份；有 serial 时不依赖可被复用的网络地址。
class DeviceGroupMember {
  DeviceGroupMember({
    required this.platform,
    required this.serial,
    required Iterable<String> aliases,
  }) : aliases = Set.unmodifiable(aliases);

  factory DeviceGroupMember.fromDevice(RegisteredDevice device) =>
      DeviceGroupMember(
        platform: DeviceGroupPlatform.of(device),
        serial: _serial(device),
        aliases: [device.id, ...device.connections],
      );

  final DeviceGroupPlatform platform;
  final String? serial;
  final Set<String> aliases;

  static String? _serial(RegisteredDevice device) {
    final serial = device.serial?.trim();
    if (serial != null &&
        serial.isNotEmpty &&
        serial != '-' &&
        !(serial == device.id && _isTransportId(serial))) {
      return serial;
    }
    // iOS 的 UDID 不随 USB/Network 变化，可直接充当物理标识。
    return device.isIos ? device.id : null;
  }

  /// 注册表在探测前以 transport ID 暂充 serial；只识别明确网络格式，
  /// 不沿用“包含点号即网络”的旧规则，避免误伤带点号的硬件序列号。
  static bool _isTransportId(String value) {
    if (RegExp(r'\._adb(?:-tls-connect)?\._tcp\.?$').hasMatch(value)) {
      return true;
    }
    if (InternetAddress.tryParse(value) != null) return true;
    final separator = value.lastIndexOf(':');
    if (separator < 0) return false;
    final port = int.tryParse(value.substring(separator + 1));
    return port != null && port >= 0 && port <= 65535;
  }

  bool matches(RegisteredDevice device) {
    if (platform != DeviceGroupPlatform.of(device)) return false;
    final candidateSerial = _serial(device);
    if (serial != null && candidateSerial != null) {
      return serial == candidateSerial || _matchesLegacyEmulatorPort(device);
    }
    if (serial != null) {
      // 身份未知的旧 IP 可能已被另一台设备占用，只允许物理通道回退。
      return [
        device.id,
        ...device.connections,
      ].any((id) => !_isTransportId(id) && aliases.contains(id));
    }
    return aliases.contains(device.id) ||
        device.connections.any(aliases.contains) ||
        (candidateSerial != null && aliases.contains(candidateSerial));
  }

  // 仅使用注册表仅归属当前 AVD 的端口升级旧分组，历史中已被复用的端口不能证明归属。
  bool _matchesLegacyEmulatorPort(RegisteredDevice device) =>
      device.emulatorAvdName != null &&
      serial != null &&
      EmulatorConnectionService.isTransport(serial!) &&
      device.emulatorIdentityAliases.contains(serial);

  /// 注册表补齐 serial 后升级身份，供后续断线和 transport 切换继续匹配。
  DeviceGroupMember synchronized(RegisteredDevice device) => DeviceGroupMember(
    platform: platform,
    serial: _matchesLegacyEmulatorPort(device)
        ? _serial(device)
        : serial ?? _serial(device),
    aliases: {...aliases, device.id, ...device.connections},
  );

  bool sameIdentity(DeviceGroupMember other) =>
      serial == other.serial &&
      aliases.length == other.aliases.length &&
      aliases.containsAll(other.aliases);

  Map<String, Object?> toJson() => {
    'platform': platform.name,
    'serial': serial,
    'aliases': aliases.toList(),
  };

  static DeviceGroupMember? fromJson(Object? value) {
    if (value is! Map) return null;
    final platform = DeviceGroupPlatform.values
        .where((item) => item.name == value['platform'])
        .firstOrNull;
    final aliases = value['aliases'];
    final serial = value['serial'];
    if (platform == null ||
        aliases is! List ||
        (serial != null && serial is! String)) {
      return null;
    }
    final validAliases = aliases.whereType<String>().where(
      (id) => id.isNotEmpty,
    );
    if (validAliases.isEmpty && (serial == null || serial.isEmpty)) return null;
    return DeviceGroupMember(
      platform: platform,
      serial: serial is String && serial.isNotEmpty ? serial : null,
      aliases: validAliases,
    );
  }
}

/// 不可变设备分组；内置平台组实时计算成员，自定义组保存用户归属。
class DeviceGroup {
  DeviceGroup({
    required this.id,
    required this.name,
    this.platform,
    Iterable<DeviceGroupMember> members = const [],
  }) : members = List.unmodifiable(members);

  final String id;
  final String name;
  final DeviceGroupPlatform? platform;
  final List<DeviceGroupMember> members;
  bool get isBuiltIn => platform != null;

  DeviceGroup copyWith({String? name, Iterable<DeviceGroupMember>? members}) =>
      DeviceGroup(
        id: id,
        name: name ?? this.name,
        platform: platform,
        members: members ?? this.members,
      );

  bool matches(RegisteredDevice device) => isBuiltIn
      ? platform == DeviceGroupPlatform.of(device)
      : members.any((member) => member.matches(device));

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'members': members.map((member) => member.toJson()).toList(),
  };
}

/// 分组快照提供统一筛选和名称校验，列表与管理弹窗共用同一套规则。
class DeviceGroupsState {
  DeviceGroupsState({Iterable<DeviceGroup> customGroups = const []})
    : groups = List.unmodifiable([
        DeviceGroup(
          id: 'android',
          name: 'Android',
          platform: DeviceGroupPlatform.android,
        ),
        DeviceGroup(
          id: 'harmony',
          name: 'Harmony',
          platform: DeviceGroupPlatform.harmony,
        ),
        DeviceGroup(id: 'ios', name: 'iOS', platform: DeviceGroupPlatform.ios),
        ...customGroups,
      ]);

  final List<DeviceGroup> groups;
  Iterable<DeviceGroup> get customGroups =>
      groups.where((group) => !group.isBuiltIn);

  bool matches(String? groupId, RegisteredDevice device) =>
      groupId == null ||
      (groups
              .where((group) => group.id == groupId)
              .firstOrNull
              ?.matches(device) ??
          false);

  /// 返回本地化错误键；null 表示名称合法。名称忽略首尾空格及大小写。
  String? validateName(String value, {String? excludingId}) {
    final name = value.trim();
    if (name.isEmpty) return 'deviceGroupNameEmpty';
    if (name.runes.length > 40) return 'deviceGroupNameTooLong';
    if (groups.any(
      (group) =>
          group.id != excludingId &&
          group.name.toLowerCase() == name.toLowerCase(),
    )) {
      return 'deviceGroupNameDuplicate';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'groups': customGroups.map((group) => group.toJson()).toList(),
  };

  /// 忽略损坏条目，保留同一快照中的有效组，始终恢复三个平台组。
  factory DeviceGroupsState.fromJson(Object? value) {
    var result = DeviceGroupsState();
    if (value is! Map || value['version'] != 1 || value['groups'] is! List) {
      throw const FormatException('Unsupported device groups snapshot');
    }
    for (final entry in value['groups'] as List) {
      if (entry is! Map) continue;
      final id = entry['id'];
      final name = entry['name'];
      final members = entry['members'];
      if (id is! String ||
          id.isEmpty ||
          name is! String ||
          members is! List ||
          result.groups.any((group) => group.id == id) ||
          result.validateName(name) != null) {
        continue;
      }
      result = DeviceGroupsState(
        customGroups: [
          ...result.customGroups,
          DeviceGroup(
            id: id,
            name: name.trim(),
            members: members
                .map(DeviceGroupMember.fromJson)
                .whereType<DeviceGroupMember>(),
          ),
        ],
      );
    }
    return result;
  }
}
