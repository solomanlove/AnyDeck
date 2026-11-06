import 'dart:async';

import '../adb/adb_service.dart';
import '../adb/discovered_device.dart';
import 'adb/shared_adb_backend.dart';
import 'device_share_invitation.dart';
import 'hosted_device_share.dart';
import 'joined_device_share.dart';

/// 共享会话的主窗口所有者；只在启停和连接变化时通知 UI。
class DeviceShareService {
  DeviceShareService(this.adb, {this.backendFactory});
  final AdbService adb;

  /// 测试可注入独立 Smart Socket，对真实运行保持本机 ADB 默认入口。
  final SharedAdbBackend Function(DiscoveredDevice device, String name)?
  backendFactory;
  final _hosts = <HostedDeviceShare>[];
  final _joins = <JoinedDeviceShare>[];
  final _changes = StreamController<int>.broadcast();
  int _revision = 0;
  bool _busy = false, _disposed = false;
  Future<void>? _closing;
  Stream<int> get changes => _changes.stream;
  List<HostedDeviceShare> get hosts =>
      List.unmodifiable(_hosts.where((h) => !h.closed));
  List<JoinedDeviceShare> get joins =>
      List.unmodifiable(_joins.where((j) => !j.closed));

  void _notify() {
    _hosts.removeWhere((host) => host.closed);
    _joins.removeWhere((joined) => joined.closed);
    if (!_disposed) _changes.add(++_revision);
  }

  Future<HostedDeviceShare> share(
    String deviceId,
    String name,
    String host,
  ) async {
    if (_busy || _disposed) throw StateError('Share operation in progress');
    final existing = hosts.where((h) => h.deviceId == deviceId).firstOrNull;
    if (existing != null) return existing;
    _busy = true;
    try {
      final devices = await adb.listDevices();
      final device = devices
          .where((d) => d.id == deviceId && d.isOnline)
          .firstOrNull;
      if (device == null ||
          device.isIos ||
          device.isHarmony ||
          device.isShared ||
          !RegExp(r'^\d+$').hasMatch(device.transportId ?? '')) {
        throw StateError('Device is not available for sharing');
      }
      final shareName = String.fromCharCodes(name.runes.take(60));
      final hosted = await HostedDeviceShare.start(
        deviceId: deviceId,
        backend:
            backendFactory?.call(device, shareName) ??
            SharedAdbBackend(transportId: device.transportId!, name: shareName),
        host: host,
        onChanged: _notify,
      );
      if (_disposed) {
        await hosted.close();
        throw StateError('Sharing stopped');
      }
      _hosts.add(hosted);
      _notify();
      return hosted;
    } finally {
      _busy = false;
    }
  }

  Future<JoinedDeviceShare> join(String code) async {
    if (_busy || _disposed) throw StateError('Share operation in progress');
    final invitation = DeviceShareInvitation.parse(code);
    if (hosts.any((h) => h.invitation.token == invitation.token) ||
        joins.any((j) => j.invitation.token == invitation.token)) {
      throw StateError('Shared device is already connected');
    }
    _busy = true;
    try {
      final joined = await JoinedDeviceShare.connect(invitation, adb, _notify);
      if (_disposed || joined.closed) {
        await joined.close();
        throw StateError('Sharing stopped');
      }
      _joins.add(joined);
      _notify();
      return joined;
    } finally {
      _busy = false;
    }
  }

  /// transport ID 是会话绑定，不允许拔线重插后自动切换到另一条 transport。
  void validateHosts(List<DiscoveredDevice> devices) {
    for (final host in hosts) {
      if (!devices.any(
        (d) =>
            d.isOnline &&
            d.id == host.deviceId &&
            d.transportId == host.backend.transportId,
      )) {
        unawaited(host.close());
      }
    }
  }

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    await Future.wait([
      ...hosts.map((h) => h.close()),
      ...joins.map((j) => j.close()),
    ]);
    await _changes.close();
  }
}
