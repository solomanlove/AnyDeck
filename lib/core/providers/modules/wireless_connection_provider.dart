import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../adb/discovered_device.dart';
import '../../adb/wireless/adb_wireless_coordinator.dart';
import '../../adb/wireless/adb_wireless_state.dart';
import 'registered_device_model.dart';
import 'service_providers.dart';

export '../../adb/wireless/adb_wireless_state.dart';

/// 主窗口连接状态独立于注册表重建，避免 track-devices 重启事件重复准备。
final wirelessConnectionProvider =
    NotifierProvider<WirelessConnectionNotifier, Map<String, AdbWirelessState>>(
      WirelessConnectionNotifier.new,
    );

class WirelessConnectionNotifier
    extends Notifier<Map<String, AdbWirelessState>> {
  late AdbWirelessCoordinator _coordinator;
  late bool _isMain;

  @override
  Map<String, AdbWirelessState> build() {
    _isMain = ref.read(windowIdProvider).isEmpty;
    _coordinator = AdbWirelessCoordinator(
      ref.read(adbServiceProvider),
      onState: (value) {
        if (ref.mounted) {
          final next = {...state}..remove(value.deviceId);
          state = {...next, value.deviceId: value};
        }
      },
    );
    ref.onDispose(_coordinator.dispose);
    return {};
  }

  /// 注册表在 build 内只提交快照，副作用延后到 microtask。
  void observe(List<DiscoveredDevice> devices) {
    if (!_isMain) return;
    scheduleMicrotask(() {
      if (ref.mounted) {
        _coordinator.observe(devices);
        _clearConnectedDevices(devices);
      }
    });
  }

  /// 若设备当前已在线且已具有网络连接通道，清理陈旧的失败状态
  void _clearConnectedDevices(List<DiscoveredDevice> devices) {
    final onlineNetworkIds = devices
        .where((d) => d.isOnline && (d.id.contains(':') || d.id.contains('.')))
        .map((d) => d.id)
        .toSet();
    if (onlineNetworkIds.isEmpty && state.isEmpty) return;

    final next = Map<String, AdbWirelessState>.from(state);
    var changed = false;

    next.removeWhere((key, val) {
      if (val.busy || !val.failed) return false;
      final ip = val.ip;
      final isOnlineNow = onlineNetworkIds.any(
        (id) => id == key || (ip != null && id.startsWith('$ip:')),
      );
      if (isOnlineNow) {
        changed = true;
        return true;
      }
      return false;
    });

    if (changed) {
      state = next;
    }
  }

  Future<AdbWirelessResult> connect(RegisteredDevice device) {
    if (!_isMain) {
      return Future.value(const AdbWirelessResult('wirelessMainOnly'));
    }
    final source = device.isOnline ? device.preferredCommandId : null;
    final serial = device.serial != null && isPhysicalUsbId(device.serial!)
        ? device.serial
        : (isPhysicalUsbId(device.id) ? device.id : null);
    return _coordinator.connect(
      key: source != null && isPhysicalUsbId(source)
          ? source
          : serial ?? device.id,
      serial: serial,
      source: source,
      ip: device.wifiIp,
      connections: device.connections,
    );
  }

  Future<void> waitForPreparation(String id) =>
      _coordinator.waitForPreparation(id);

  /// 概览探针晚于自动准备取得 IP 时，更新连接缓存并清除过期的无地址失败状态。
  void syncDiscoveredIp(String deviceId, String ip) {
    final validIp = wirelessIpv4(ip);
    if (validIp == null) return;
    _coordinator.rememberIp(deviceId, validIp);
    final next = reconcileDiscoveredIp(state, deviceId, validIp);
    if (!identical(next, state)) state = next;
  }

  Future<AdbWirelessResult> pair(String address, String code) => _isMain
      ? _coordinator.pair(address, code)
      : Future.value(const AdbWirelessResult('wirelessMainOnly'));
}

/// 用概览探针的最新地址修正同设备过期的 `wirelessNoIp` 状态。
Map<String, AdbWirelessState> reconcileDiscoveredIp(
  Map<String, AdbWirelessState> states,
  String deviceId,
  String ip,
) {
  MapEntry<String, AdbWirelessState>? matched;
  for (final entry in states.entries.toList().reversed) {
    if (entry.key == deviceId ||
        entry.value.deviceId == deviceId ||
        entry.value.serial == deviceId) {
      matched = entry;
      break;
    }
  }
  if (matched == null ||
      matched.value.busy ||
      matched.value.messageKey != 'wirelessNoIp') {
    return states;
  }

  final current = matched.value;
  return {
    ...states,
    matched.key: AdbWirelessState(
      deviceId: current.deviceId,
      messageKey: 'wirelessReady',
      ip: ip,
      serial: current.serial,
    ),
  };
}

/// 合并前后都可使用 USB ID 或硬件 serial 找到同一份连接进度。
AdbWirelessState? wirelessStateFor(
  Map<String, AdbWirelessState> states,
  RegisteredDevice device,
) {
  final ids = {device.id, device.serial, ...device.connections};
  for (final value in states.values.toList().reversed) {
    if (ids.contains(value.deviceId) ||
        (value.serial != null && ids.contains(value.serial))) {
      // 若设备当前已在线且已建立无线连接通道，且非执行中状态，历史失败状态不再生效
      if (value.failed &&
          !value.busy &&
          device.isOnline &&
          (device.hasTcpConnection || device.hasWifiDebuggingConnection)) {
        return null;
      }
      return value;
    }
  }
  return null;
}
