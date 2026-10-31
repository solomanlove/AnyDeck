import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../adb/adb_result.dart';
import '../../adb/discovered_device.dart';
import '../../harmony/hdc_service_device_info.dart';
import '../../harmony/wireless/harmony_wireless_models.dart';
import 'device_tracking_providers.dart';
import 'service_providers.dart';

final harmonyWirelessConnectionProvider =
    NotifierProvider<HarmonyWirelessNotifier, HarmonyWirelessState>(
      HarmonyWirelessNotifier.new,
    );

/// 管理 HarmonyOS HDC 历史端点、身份绑定及有界自动重连。
class HarmonyWirelessNotifier extends Notifier<HarmonyWirelessState> {
  static const _historyKey = 'harmony.wireless.history';
  static const _autoReconnectKey = 'harmony.wireless.autoReconnect';
  static const _maxHistory = 8;

  Timer? _reconnectTimer;
  Set<String> _onlineAddresses = {};
  List<DiscoveredDevice> _harmonyDevices = const [];
  final Set<String> _suppressedIdentities = {};
  int _reconnectFailureCount = 0;
  bool _disposed = false;
  late Future<void> _loadFuture;

  @override
  HarmonyWirelessState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _reconnectTimer?.cancel();
    });
    ref.listen(discoveredDevicesProvider, (_, next) {
      final previousAddresses = _onlineAddresses;
      _harmonyDevices =
          next.value?.where((device) => device.isHarmony).toList() ?? const [];
      _onlineAddresses = _harmonyDevices
          .where((device) => device.id.contains(':'))
          .map((device) => device.id)
          .toSet();
      if (!_sameSet(previousAddresses, _onlineAddresses)) {
        _reconnectFailureCount = 0;
      }
      _scheduleReconnect();
    });
    _loadFuture = Future.microtask(_load);
    return const HarmonyWirelessState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawHistory = prefs.getStringList(_historyKey) ?? const [];
    final history = <HarmonyWirelessEndpoint>[];
    for (final raw in rawHistory) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final address = normalizeHarmonyEndpoint(
          json['address'] as String? ?? '',
        );
        if (address == null) continue;
        history.add(
          HarmonyWirelessEndpoint(
            address: address,
            deviceSerial: json['deviceSerial'] as String?,
            lastConnectedAt: DateTime.tryParse(
              json['lastConnectedAt'] as String? ?? '',
            ),
          ),
        );
      } catch (_) {
        // 忽略旧版本或损坏的单条历史记录。
      }
    }
    if (_disposed) return;
    state = state.copyWith(
      history: history,
      autoReconnect: prefs.getBool(_autoReconnectKey) ?? true,
    );
    _scheduleReconnect();
  }

  Future<AdbResult> connect(
    String input, {
    bool remember = true,
    String? expectedSerial,
  }) async {
    await _loadFuture;
    final address = normalizeHarmonyEndpoint(input);
    if (address == null) {
      return const AdbResult(
        exitCode: 2,
        stdout: '',
        stderr: 'Invalid HarmonyOS IP:Port',
      );
    }
    if (state.connectingAddress != null) {
      return const AdbResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Another HDC connection is in progress',
      );
    }
    state = state.copyWith(
      connectingAddress: address,
      clearError: true,
      messageKey: 'harmonyConnecting',
    );
    final result = await ref.read(hdcServiceProvider).connectWireless(address);
    if (_disposed) return result;
    if (result.isSuccess || result.stdout.contains('Connect OK')) {
      final actualSerial = await ref
          .read(hdcServiceProvider)
          .getDeviceSerial(address);
      if (actualSerial == null) {
        await ref.read(hdcServiceProvider).disconnectWireless(address);
        const unknown = AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: 'Unable to verify HarmonyOS device identity',
        );
        state = state.copyWith(
          clearConnectingAddress: true,
          error: unknown.message,
          messageKey: 'wirelessIdentityUnknown',
        );
        return unknown;
      }
      if (expectedSerial != null && actualSerial != expectedSerial) {
        await ref.read(hdcServiceProvider).disconnectWireless(address);
        const mismatch = AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: 'HarmonyOS device identity mismatch',
        );
        state = state.copyWith(
          clearConnectingAddress: true,
          error: mismatch.message,
          messageKey: 'wirelessIdentityMismatch',
        );
        return mismatch;
      }
      _reconnectFailureCount = 0;
      _suppressedIdentities.remove(actualSerial);
      if (remember) await _remember(address, actualSerial);
      state = state.copyWith(
        clearConnectingAddress: true,
        messageKey: 'harmonyConnectSuccess',
      );
    } else {
      state = state.copyWith(
        clearConnectingAddress: true,
        error: result.message,
        messageKey: 'harmonyConnectFailed',
      );
    }
    return result;
  }

  Future<AdbResult> disconnect(String input) async {
    final address = normalizeHarmonyEndpoint(input);
    if (address == null) {
      return const AdbResult(
        exitCode: 2,
        stdout: '',
        stderr: 'Invalid HarmonyOS IP:Port',
      );
    }
    final endpoint = state.history
        .where((item) => item.address == address)
        .firstOrNull;
    _suppressedIdentities.add(endpoint?.deviceSerial ?? address);
    _reconnectTimer?.cancel();
    return ref.read(hdcServiceProvider).disconnectWireless(address);
  }

  Future<void> removeHistory(String address) async {
    if (_onlineAddresses.contains(address)) {
      await disconnect(address);
    }
    final next = state.history
        .where((item) => item.address != address)
        .toList();
    state = state.copyWith(history: next);
    await _saveHistory(next);
  }

  Future<void> setAutoReconnect(bool value) async {
    state = state.copyWith(autoReconnect: value);
    if (value) {
      _suppressedIdentities.clear();
      _reconnectFailureCount = 0;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoReconnectKey, value);
    _scheduleReconnect();
  }

  Future<void> _remember(String address, String? deviceSerial) async {
    final next = [
      HarmonyWirelessEndpoint(
        address: address,
        deviceSerial: deviceSerial,
        lastConnectedAt: DateTime.now(),
      ),
      ...state.history.where((item) => item.address != address),
    ].take(_maxHistory).toList();
    state = state.copyWith(history: next);
    await _saveHistory(next);
  }

  Future<void> _saveHistory(List<HarmonyWirelessEndpoint> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _historyKey,
      history
          .map(
            (item) => jsonEncode({
              'address': item.address,
              'deviceSerial': item.deviceSerial,
              'lastConnectedAt': item.lastConnectedAt?.toIso8601String(),
            }),
          )
          .toList(),
    );
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_disposed || !state.autoReconnect || state.history.isEmpty) return;
    if (_reconnectFailureCount >= 5) return;
    final endpoint = state.history.first;
    // 旧版本仅保存裸地址，必须由用户手动连接并完成身份绑定后才允许自动重连。
    if (endpoint.deviceSerial == null) return;
    final identity = endpoint.deviceSerial ?? endpoint.address;
    if (_suppressedIdentities.contains(identity)) return;
    final target = endpoint.address;
    if (_onlineAddresses.contains(target) || state.connectingAddress != null) {
      return;
    }
    final seconds = switch (_reconnectFailureCount) {
      0 => 3,
      1 => 10,
      2 => 30,
      _ => 60,
    };
    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      if (_disposed || _onlineAddresses.contains(target)) return;
      final refreshedTarget = await _targetFromUsb(endpoint) ?? target;
      final result = await connect(
        refreshedTarget,
        remember: refreshedTarget != target,
        expectedSerial: endpoint.deviceSerial,
      );
      if (!result.isSuccess) {
        _reconnectFailureCount++;
      }
      _scheduleReconnect();
    });
  }

  Future<String?> _targetFromUsb(HarmonyWirelessEndpoint endpoint) async {
    final expected = endpoint.deviceSerial;
    if (expected == null) return null;
    final hdc = ref.read(hdcServiceProvider);
    for (final device in _harmonyDevices.where(
      (item) => !item.id.contains(':'),
    )) {
      final serial = await hdc.getDeviceSerial(device.id);
      if (serial != expected) continue;
      final ip = await hdc.getDeviceIp(device.id);
      if (ip != null) return '$ip:${endpoint.port}';
    }
    return null;
  }

  bool _sameSet(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);
}
