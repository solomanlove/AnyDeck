import 'dart:async';

import '../adb/discovered_device.dart';
import '../network/host_network_info.dart';
import 'device_share_models.dart';
import 'hosted_device_share.dart';

/// 自动准备所需的当前网络、在线设备与物理身份，不猜测当前 Wi-Fi。
class DeviceShareEnvironment {
  const DeviceShareEnvironment({
    required this.network,
    required this.devices,
    this.serials = const {},
  });
  final HostNetworkInfo network;
  final List<DiscoveredDevice> devices;
  final Map<String, String> serials;
}

/// 按网络进入次数维护授权窗口，避免定时到期后被下一次状态通知立即重开。
class DeviceShareAutoPrepare {
  DeviceShareAutoPrepare({
    required this.profiles,
    required this.hosts,
    required this.busy,
    required this.start,
    required this.now,
  });
  final List<SavedDeviceShare> Function() profiles;
  final List<HostedDeviceShare> Function() hosts;
  final bool Function() busy;
  final DateTime Function() now;
  final Future<HostedDeviceShare> Function(
    SavedDeviceShare,
    DiscoveredDevice,
    String,
    DateTime?,
  )
  start;
  DeviceShareEnvironment? _environment;
  final _windows = <String, ({int epoch, DateTime? deadline})>{};
  Future<void>? _running;
  bool _again = false, _closed = false;
  int _epoch = 0;
  String? _ssid;

  Future<void> update(DeviceShareEnvironment environment) {
    _environment = environment;
    final ssid = environment.network.verifiedWifiSsid;
    if (ssid != _ssid) {
      _ssid = ssid;
      _epoch++;
    }
    request();
    return _settle();
  }

  Future<void> _settle() async {
    while (_running != null) {
      await _running;
    }
  }

  void reset(String id) => _windows.remove(id);

  bool isExpired(String id) {
    final window = _windows[id];
    return window != null &&
        window.epoch == _epoch &&
        window.deadline != null &&
        !window.deadline!.isAfter(now());
  }

  /// 手动开始的窗口沿用原到期时间，USB 重插或 DHCP 更新不会续期。
  void remember(SavedDeviceShare profile, HostedDeviceShare host) {
    _windows[profile.id] = (epoch: _epoch, deadline: host.invitation.expiresAt);
  }

  void request() {
    if (_closed) return;
    _again = true;
    _running ??= _drain().whenComplete(() {
      _running = null;
      if (_again && !_closed) request();
    });
  }

  Future<void> _drain() async {
    while (_again && !_closed) {
      _again = false;
      if (busy()) return;
      final environment = _environment;
      if (environment == null) return;
      for (final profile in profiles().where((p) => p.automaticallyPrepares)) {
        if (_closed || busy()) return;
        final network = environment.network;
        final address =
            network.verifiedWifiSsid == profile.wifiSsid &&
                network.isWifiAddress
            ? network.address?.ipv4
            : null;
        final device = environment.devices
            .where(
              (device) =>
                  device.isOnline &&
                  RegExp(r'^\d+$').hasMatch(device.transportId ?? '') &&
                  !device.isShared &&
                  !device.isIos &&
                  !device.isHarmony &&
                  (device.id == profile.serial ||
                      device.id == profile.deviceId ||
                      environment.serials[device.id] == profile.serial),
            )
            .firstOrNull;
        final hosted = hosts()
            .where((host) => host.invitation.fingerprint == profile.id)
            .firstOrNull;
        if (hosted != null &&
            (address == null ||
                device == null ||
                hosted.invitation.host != address ||
                hosted.backend.transportId != device.transportId)) {
          await hosted.close();
        }
        if (address == null || device == null || _closed) continue;
        var window = _windows[profile.id];
        if (window == null || window.epoch != _epoch) {
          window = (
            epoch: _epoch,
            deadline: profile.lifetime.duration == null
                ? null
                : now().add(profile.lifetime.duration!),
          );
          _windows[profile.id] = window;
        }
        if (window.deadline != null && !window.deadline!.isAfter(now())) {
          continue;
        }
        if (hosts().any((host) => host.invitation.fingerprint == profile.id)) {
          continue;
        }
        final epoch = _epoch;
        try {
          final host = await start(profile, device, address, window.deadline);
          // 切网或停止规则发生在连接建立期间时，回收迟到会话。
          final current = _environment;
          if (_closed ||
              epoch != _epoch ||
              current?.network.verifiedWifiSsid != profile.wifiSsid ||
              current?.network.address?.ipv4 != address ||
              current?.devices.any(
                    (d) =>
                        d.isOnline &&
                        d.id == device.id &&
                        d.transportId == device.transportId,
                  ) !=
                  true ||
              !profiles().any(
                (p) => p.id == profile.id && p.automaticallyPrepares,
              )) {
            await host.close();
          }
        } catch (_) {
          // 后续设备/网络变化可重试；不记录凭据，不启动即时无限重试。
        }
      }
    }
  }

  Future<void> dispose() async {
    _closed = true;
    await _running;
  }
}
