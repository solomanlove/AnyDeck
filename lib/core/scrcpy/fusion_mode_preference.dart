import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../adb/adb_service.dart';
import '../providers/app_providers.dart';

enum FusionModeState { enabled, disabled, unsupported, unknown }

/// 融合投屏只记录用户显式选择；未知设备身份不写入临时网络地址。
class FusionModeStatus {
  const FusionModeStatus(this.state, {this.physicalDeviceKey, this.sdkVersion});

  final FusionModeState state;
  final String? physicalDeviceKey;
  final int? sdkVersion;

  bool get canChange =>
      physicalDeviceKey != null &&
      (state == FusionModeState.enabled || state == FusionModeState.disabled);
}

abstract class FusionModeStore {
  Future<bool?> read(String key);
  Future<void> write(String key, bool enabled);
}

class _SharedPreferencesFusionModeStore implements FusionModeStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<bool?> read(String key) => _preferences.getBool(key);

  @override
  Future<void> write(String key, bool enabled) =>
      _preferences.setBool(key, enabled);
}

/// 每次操作从无缓存的存储读取，子窗口 Isolate 能看到主窗口刚保存的选择。
class FusionModePreference {
  FusionModePreference(this._adb, {FusionModeStore? store})
    : _store = store ?? _SharedPreferencesFusionModeStore();

  final AdbService _adb;
  final FusionModeStore _store;

  static String? knownPhysicalKey(RegisteredDevice? device, String deviceId) {
    final serial = device?.serial?.trim();
    if (_isPhysicalSerial(serial)) return serial;
    if (_isPhysicalSerial(deviceId)) return deviceId;
    return null;
  }

  static bool _isPhysicalSerial(String? value) =>
      value != null &&
      value.isNotEmpty &&
      value != 'unknown' &&
      value != '-' &&
      !value.contains(':') &&
      !value.contains('.') &&
      !value.startsWith('harmony:');

  Future<FusionModeStatus> resolve(
    String deviceId, {
    RegisteredDevice? device,
    bool refreshSdk = false,
  }) async {
    if (device?.isIos == true || device?.isHarmony == true) {
      return const FusionModeStatus(FusionModeState.unsupported);
    }
    var sdk = device?.sdkVersion;
    if (sdk == null || refreshSdk) {
      sdk = null;
      final result = await _adb.shellArgs(deviceId, [
        'getprop',
        'ro.build.version.sdk',
      ], timeout: const Duration(seconds: 8));
      if (result.isSuccess) sdk = int.tryParse(result.stdout.trim());
    }
    if (sdk == null) return const FusionModeStatus(FusionModeState.unknown);
    if (sdk < 34) {
      return FusionModeStatus(FusionModeState.unsupported, sdkVersion: sdk);
    }

    var identity = knownPhysicalKey(device, deviceId);
    if (identity == null) {
      for (final property in const ['ro.serialno', 'ro.boot.serialno']) {
        final result = await _adb.shellArgs(deviceId, [
          'getprop',
          property,
        ], timeout: const Duration(seconds: 5));
        if (result.isSuccess && _isPhysicalSerial(result.stdout.trim())) {
          identity = result.stdout.trim();
          break;
        }
      }
    }
    if (identity == null) {
      return FusionModeStatus(FusionModeState.unknown, sdkVersion: sdk);
    }
    bool enabled;
    try {
      enabled = await _store.read(_key(identity)) ?? true;
    } catch (_) {
      return FusionModeStatus(FusionModeState.unknown, sdkVersion: sdk);
    }
    return FusionModeStatus(
      enabled ? FusionModeState.enabled : FusionModeState.disabled,
      physicalDeviceKey: identity,
      sdkVersion: sdk,
    );
  }

  Future<void> setEnabled(String physicalDeviceKey, bool enabled) {
    if (!_isPhysicalSerial(physicalDeviceKey)) {
      throw ArgumentError.value(physicalDeviceKey, 'physicalDeviceKey');
    }
    return _store.write(_key(physicalDeviceKey), enabled);
  }

  static String _key(String identity) =>
      'settings.fusionMirror.${Uri.encodeComponent(identity)}';
}

final fusionModePreferenceProvider = Provider<FusionModePreference>((ref) {
  return FusionModePreference(ref.watch(adbServiceProvider));
});

final deviceFusionModeProvider = FutureProvider.autoDispose
    .family<FusionModeStatus, String>((ref, deviceId) {
      final devices = ref.watch(deviceRegistryProvider);
      RegisteredDevice? device;
      for (final candidate in devices) {
        if (candidate.id == deviceId ||
            candidate.serial == deviceId ||
            candidate.connections.contains(deviceId)) {
          device = candidate;
          break;
        }
      }
      return ref
          .read(fusionModePreferenceProvider)
          .resolve(deviceId, device: device);
    });
