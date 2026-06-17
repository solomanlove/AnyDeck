import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../adb/adb_service.dart';
import '../utils/network_util.dart';
import 'app_providers.dart';

/// 设备 HTTP 代理配置，rawValue 保留 adb 原始读取结果便于兼容不同 ROM。
class DeviceProxyConfig {
  const DeviceProxyConfig({
    required this.host,
    required this.port,
    required this.rawValue,
    required this.isEnabled,
  });

  final String host;
  final int? port;
  final String rawValue;
  final bool isEnabled;

  String get address => isEnabled && port != null ? '$host:$port' : '';
}

/// 不区分设备的 HTTP 代理默认输入值。
class DeviceProxyDefaults {
  const DeviceProxyDefaults({required this.host, required this.port});

  final String host;
  final int port;
}

/// 读取全局代理默认值；未持久化时使用当前电脑的局域网 IPv4。
Future<DeviceProxyDefaults> loadDeviceProxyDefaults() async {
  final prefs = await SharedPreferences.getInstance();
  final savedHost = prefs.getString(_deviceProxyHostKey)?.trim();
  final savedPort = prefs.getInt(_deviceProxyPortKey);
  final host = savedHost != null && savedHost.isNotEmpty
      ? savedHost
      : await NetworkLanMatcher.preferredHostIpv4() ?? '127.0.0.1';
  return DeviceProxyDefaults(host: host, port: savedPort ?? 8888);
}

/// 保存最近一次成功应用的代理输入，作为所有设备共享的下次默认值。
Future<void> saveDeviceProxyDefaults({
  required String host,
  required int port,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_deviceProxyHostKey, host);
  await prefs.setInt(_deviceProxyPortKey, port);
}

const _deviceProxyHostKey = 'network.device_proxy.host';
const _deviceProxyPortKey = 'network.device_proxy.port';

/// 端口转发数据模型
class PortForward {
  const PortForward({required this.devicePort, required this.localPort});

  final String devicePort;
  final String localPort;

  String get displayDevicePort =>
      devicePort.startsWith('tcp:') ? devicePort.substring(4) : devicePort;
  String get displayLocalPort =>
      localPort.startsWith('tcp:') ? localPort.substring(4) : localPort;

  @override
  bool operator ==(Object other) {
    return other is PortForward &&
        other.devicePort == devicePort &&
        other.localPort == localPort;
  }

  @override
  int get hashCode => Object.hash(devicePort, localPort);
}

/// 端口转发预设数据模型
class PortForwardPreset {
  const PortForwardPreset({
    required this.name,
    required this.devicePort,
    required this.localPort,
    required this.autoApply,
  });

  final String name;
  final String devicePort;
  final String localPort;
  final bool autoApply;

  Map<String, dynamic> toJson() => {
    'name': name,
    'devicePort': devicePort,
    'localPort': localPort,
    'autoApply': autoApply,
  };

  factory PortForwardPreset.fromJson(Map<String, dynamic> json) =>
      PortForwardPreset(
        name: json['name'] ?? '',
        devicePort: json['devicePort'] ?? '',
        localPort: json['localPort'] ?? '',
        autoApply: json['autoApply'] ?? false,
      );

  @override
  bool operator ==(Object other) {
    return other is PortForwardPreset &&
        other.name == name &&
        other.devicePort == devicePort &&
        other.localPort == localPort &&
        other.autoApply == autoApply;
  }

  @override
  int get hashCode => Object.hash(name, devicePort, localPort, autoApply);
}

/// 解析 `adb reverse --list` 输出内容
List<PortForward> parseReverseList(String stdout) {
  final lines = stdout.split('\n');
  final list = <PortForward>[];
  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      // 格式如: <serial> tcp:8081 tcp:8081
      list.add(PortForward(devicePort: parts[1], localPort: parts[2]));
    } else if (parts.length == 2) {
      // 格式如: tcp:8081 tcp:8081
      list.add(PortForward(devicePort: parts[0], localPort: parts[1]));
    }
  }
  return list;
}

/// 解析 Android global http_proxy 字段，兼容空值、null、:0 等未设置状态。
DeviceProxyConfig parseDeviceHttpProxy(String stdout) {
  final rawValue = stdout.trim();
  if (rawValue.isEmpty || rawValue == 'null' || rawValue == ':0') {
    return DeviceProxyConfig(
      host: '',
      port: null,
      rawValue: rawValue,
      isEnabled: false,
    );
  }

  final separator = rawValue.lastIndexOf(':');
  if (separator <= 0 || separator >= rawValue.length - 1) {
    return DeviceProxyConfig(
      host: rawValue,
      port: null,
      rawValue: rawValue,
      isEnabled: rawValue.isNotEmpty,
    );
  }

  return DeviceProxyConfig(
    host: rawValue.substring(0, separator),
    port: int.tryParse(rawValue.substring(separator + 1)),
    rawValue: rawValue,
    isEnabled: true,
  );
}

/// 实时获取设备的端口转发列表的 Provider
final activePortForwardsProvider = FutureProvider.autoDispose
    .family<List<PortForward>, String>((ref, deviceId) async {
      final adb = ref.watch(adbServiceProvider);
      final result = await adb.run(['-s', deviceId, 'reverse', '--list']);
      if (!result.isSuccess) {
        return [];
      }
      return parseReverseList(result.stdout);
    });

/// 读取当前设备的全局 HTTP 代理状态。
final deviceHttpProxyProvider = FutureProvider.autoDispose
    .family<DeviceProxyConfig, String>((ref, deviceId) async {
      final adb = ref.watch(adbServiceProvider);
      await _readAndroidSdkVersion(adb, deviceId);
      final httpProxy = await _readSettingsValue(adb, deviceId, 'http_proxy');
      final proxy = parseDeviceHttpProxy(httpProxy);
      if (proxy.isEnabled) {
        return proxy;
      }

      final legacyHost = await _readSettingsValue(
        adb,
        deviceId,
        'global_http_proxy_host',
      );
      final legacyPort = await _readSettingsValue(
        adb,
        deviceId,
        'global_http_proxy_port',
      );
      final port = int.tryParse(legacyPort.trim());
      if (legacyHost.trim().isNotEmpty &&
          legacyHost.trim() != 'null' &&
          port != null) {
        return DeviceProxyConfig(
          host: legacyHost.trim(),
          port: port,
          rawValue: '${legacyHost.trim()}:$port',
          isEnabled: true,
        );
      }

      return proxy;
    });

/// 设备 HTTP 代理操作控制器，state 用于标记按钮加载状态。
class DeviceProxyController extends Notifier<bool> {
  DeviceProxyController(this.deviceId);

  final String deviceId;

  @override
  bool build() => false;

  Future<void> apply({required String host, required int port}) async {
    state = true;
    try {
      final adb = ref.read(adbServiceProvider);
      await _readAndroidSdkVersion(adb, deviceId);
      await _runSettingsCommand(adb, [
        'put',
        'global',
        'http_proxy',
        '$host:$port',
      ]);
      await _runSettingsCommand(adb, [
        'put',
        'global',
        'global_http_proxy_host',
        host,
      ]);
      await _runSettingsCommand(adb, [
        'put',
        'global',
        'global_http_proxy_port',
        '$port',
      ]);
      await _runStaticShellCommand(
        adb,
        'settings put global global_http_proxy_exclusion_list ""',
      );
      ref.invalidate(deviceHttpProxyProvider(deviceId));
    } finally {
      state = false;
    }
  }

  Future<void> clear() async {
    state = true;
    try {
      final adb = ref.read(adbServiceProvider);
      await _readAndroidSdkVersion(adb, deviceId);
      await _runSettingsCommand(adb, ['put', 'global', 'http_proxy', ':0']);
      await _runStaticShellCommand(
        adb,
        'settings put global global_http_proxy_host ""',
      );
      await _runSettingsCommand(adb, [
        'put',
        'global',
        'global_http_proxy_port',
        '0',
      ]);
      await _runStaticShellCommand(
        adb,
        'settings put global global_http_proxy_exclusion_list ""',
      );
      ref.invalidate(deviceHttpProxyProvider(deviceId));
    } finally {
      state = false;
    }
  }

  Future<void> _runSettingsCommand(
    AdbService adb,
    List<String> settingsArgs,
  ) async {
    final result = await adb.run([
      '-s',
      deviceId,
      'shell',
      'settings',
      ...settingsArgs,
    ]);
    if (!result.isSuccess) {
      throw Exception(result.message);
    }
  }

  Future<void> _runStaticShellCommand(AdbService adb, String command) async {
    final result = await adb.shell(deviceId, command);
    if (!result.isSuccess) {
      throw Exception(result.message);
    }
  }
}

/// 当前设备 HTTP 代理操作状态。
final deviceProxyControllerProvider =
    NotifierProvider.family<DeviceProxyController, bool, String>(
      DeviceProxyController.new,
    );

/// 读取 Android SDK 级别，确保后续兼容分支基于设备真实系统版本执行。
Future<int?> _readAndroidSdkVersion(AdbService adb, String deviceId) async {
  final result = await adb.run([
    '-s',
    deviceId,
    'shell',
    'getprop',
    'ro.build.version.sdk',
  ]);
  if (!result.isSuccess) {
    throw Exception(result.message);
  }
  return int.tryParse(result.stdout.trim());
}

Future<String> _readSettingsValue(
  AdbService adb,
  String deviceId,
  String key,
) async {
  final result = await adb.run([
    '-s',
    deviceId,
    'shell',
    'settings',
    'get',
    'global',
    key,
  ]);
  if (!result.isSuccess) {
    throw Exception(result.message);
  }
  return result.stdout;
}

/// 预设列表状态管理 Notifier
class PortForwardPresetsNotifier extends Notifier<List<PortForwardPreset>> {
  static const _prefsKey = 'network.port_forward_presets';

  @override
  List<PortForwardPreset> build() {
    _loadPresets();
    return [];
  }

  Future<void> _loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? [];
    state = list
        .map((item) {
          try {
            return PortForwardPreset.fromJson(jsonDecode(item));
          } catch (_) {
            return null;
          }
        })
        .whereType<PortForwardPreset>()
        .toList();
  }

  Future<void> savePreset(PortForwardPreset preset) async {
    final updated = [...state];
    // 根据名称或配置排重
    updated.removeWhere(
      (p) =>
          p.name == preset.name ||
          (p.devicePort == preset.devicePort &&
              p.localPort == preset.localPort),
    );
    updated.add(preset);
    state = updated;
    await _syncToPrefs();
  }

  Future<void> deletePreset(PortForwardPreset preset) async {
    state = state.where((p) => p != preset).toList();
    await _syncToPrefs();
  }

  /// 在设备连接或选中时自动应用所有标记为自动应用的预设
  Future<void> autoApplyPresets(String deviceId) async {
    final autoPresets = state.where((p) => p.autoApply).toList();
    if (autoPresets.isEmpty) return;

    final adb = ref.read(adbServiceProvider);
    for (final preset in autoPresets) {
      final devPort = preset.devicePort.startsWith('tcp:')
          ? preset.devicePort
          : 'tcp:${preset.devicePort}';
      final locPort = preset.localPort.startsWith('tcp:')
          ? preset.localPort
          : 'tcp:${preset.localPort}';
      await adb.run(['-s', deviceId, 'reverse', devPort, locPort]);
    }
    // 强制触发列表刷新
    ref.invalidate(activePortForwardsProvider(deviceId));
  }

  Future<void> _syncToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = state.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_prefsKey, jsonList);
  }
}

/// 预设列表的 Provider
final portForwardPresetsProvider =
    NotifierProvider<PortForwardPresetsNotifier, List<PortForwardPreset>>(
      PortForwardPresetsNotifier.new,
    );

/// 监听设备选中以自动应用端口转发的 Provider
final portForwardAutoApplyProvider = Provider.autoDispose<void>((ref) {
  final device = ref.watch(selectedDeviceProvider);
  if (device != null && device.isOnline) {
    Future.microtask(() {
      ref.read(portForwardPresetsProvider.notifier).autoApplyPresets(device.id);
    });
  }
});
