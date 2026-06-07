import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_providers.dart';

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
