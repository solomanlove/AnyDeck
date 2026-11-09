import 'dart:async';
import 'dart:io';

import '../adb/adb_service.dart';
import '../adb/discovered_device.dart';
import 'adb/shared_adb_backend.dart';
import 'device_share_auto_prepare.dart';
import 'device_share_discovery.dart';
import 'device_share_invitation.dart';
import 'device_share_models.dart';
import 'device_share_store.dart';
import 'hosted_device_share.dart';
import 'joined_device_share.dart';
import 'share_tls_identity.dart';

/// 主窗口独占共享会话、私有历史与自动准备规则，数据传输不经过通知流。
class DeviceShareService {
  DeviceShareService(
    this.adb, {
    this.backendFactory,
    DeviceShareStore? store,
    this.discovery,
    DateTime Function()? now,
  }) : _store = store ?? MemoryDeviceShareStore(),
       now = now ?? DateTime.now {
    _automatic = DeviceShareAutoPrepare(
      profiles: () => profiles,
      hosts: () => hosts,
      busy: () => _busy,
      start: (profile, device, address, deadline) => _operate(() async {
        await _verifyIdentity(device, profile.serial);
        return _startProfile(profile, device, address, expiresAt: deadline);
      }, automatic: true),
      now: this.now,
    );
  }
  final AdbService adb;
  final SharedAdbBackend Function(DiscoveredDevice device, String name)?
  backendFactory;
  final DeviceShareStore _store;
  final DeviceShareDiscovery? discovery;
  final DateTime Function() now;
  final _hosts = <HostedDeviceShare>[];
  final _joins = <JoinedDeviceShare>[];
  final _changes = StreamController<int>.broadcast();
  late final DeviceShareAutoPrepare _automatic;
  List<SavedDeviceShare> _profiles = [];
  List<DeviceShareHistoryEntry> _history = [];
  int _revision = 0;
  bool _busy = false, _disposed = false;
  DeviceShareEnvironment? _environment;
  Future<void>? _closing, _initializing, _operation;
  bool ready = false;
  Object? initializationError;
  Stream<int> get changes => _changes.stream;
  List<HostedDeviceShare> get hosts =>
      List.unmodifiable(_hosts.where((h) => !h.closed));
  List<JoinedDeviceShare> get joins =>
      List.unmodifiable(_joins.where((j) => !j.closed));
  List<SavedDeviceShare> get profiles => List.unmodifiable(_profiles);
  List<DeviceShareHistoryEntry> get history => List.unmodifiable(_history);
  bool get hasAutomaticShares => profiles.any((p) => p.automaticallyPrepares);
  bool hasExpiredWindow(String id) => _automatic.isExpired(id);

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    try {
      final state = await _store.load();
      if (_disposed) return;
      _profiles = state.profiles;
      _history = state.history;
      ready = true;
      _notify();
      _automatic.request();
    } catch (error) {
      initializationError = error;
      _notify();
      rethrow;
    }
  }

  Future<T> _operate<T>(
    Future<T> Function() action, {
    bool automatic = false,
  }) async {
    await initialize();
    // 自动准备可能正在握手；用户的停止/删除操作排队执行，不能因短暂 busy 被丢弃。
    while (_busy && !automatic && !_disposed) {
      await _operation;
    }
    if (_busy || _disposed) throw StateError('Share operation in progress');
    _busy = true;
    try {
      final result = action();
      _operation = result.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      return await result;
    } finally {
      _busy = false;
      if (!automatic) _automatic.request();
    }
  }

  void _notify() {
    _hosts.removeWhere((host) => host.closed);
    _joins.removeWhere((joined) => joined.closed);
    if (!_disposed) {
      _changes.add(++_revision);
      unawaited(
        discovery
                ?.publish(hosts.map((host) => host.invitation).toList())
                .catchError((Object _, StackTrace _) {}) ??
            Future<void>.value(),
      );
    }
  }

  Future<void> _save({
    List<SavedDeviceShare>? profiles,
    List<DeviceShareHistoryEntry>? history,
  }) async {
    final state = DeviceShareSavedState(
      profiles: List.unmodifiable(profiles ?? _profiles),
      history: List.unmodifiable(history ?? _history),
    );
    await _store.save(state);
    _profiles = state.profiles;
    _history = state.history;
    _notify();
  }

  /// 再次配置沿用身份，以便接收方历史重连；删除规则才撤销保存的访问凭据。
  Future<HostedDeviceShare> share(
    String deviceId,
    String name,
    String host, {
    DeviceShareLifetime lifetime = DeviceShareLifetime.minutes30,
    String? wifiSsid,
    String? serial,
  }) => _operate(() async {
    final device = await _device(deviceId);
    final sourceSerial = await _serial(device, serial);
    if (wifiSsid != null &&
        (wifiSsid.isEmpty ||
            sourceSerial == device.id &&
                (device.id.contains(':') || device.id.startsWith('adb-')))) {
      throw StateError('deviceShareAutoNeedsIdentity');
    }
    final existing = profiles
        .where((p) => p.serial == sourceSerial || p.deviceId == deviceId)
        .firstOrNull;
    final shareName = String.fromCharCodes(name.runes.take(60));
    final profile =
        existing?.copyWith(
          deviceId: deviceId,
          serial: sourceSerial,
          name: shareName,
          lifetime: lifetime,
          wifiSsid: wifiSsid,
          clearWifi: wifiSsid == null,
          enabled: true,
          lastHost: host,
        ) ??
        SavedDeviceShare(
          deviceId: deviceId,
          serial: sourceSerial,
          name: shareName,
          identity: await ShareTlsIdentity.generate(persistent: true),
          token: DeviceShareInvitation.createToken(),
          lifetime: lifetime,
          wifiSsid: wifiSsid,
          lastHost: host,
        );
    final active = hosts
        .where((h) => h.invitation.fingerprint == profile.id)
        .firstOrNull;
    if (active != null &&
        active.invitation.host == host &&
        existing?.lifetime == lifetime &&
        existing?.wifiSsid == wifiSsid) {
      return active;
    }
    await active?.close();
    await _save(
      profiles: [...profiles.where((p) => p.id != profile.id), profile],
    );
    _automatic.reset(profile.id);
    final hosted = await _startProfile(profile, device, host);
    _automatic.remember(profile, hosted);
    return hosted;
  });

  Future<DiscoveredDevice> _device(String id, {String? serial}) async {
    final devices = await adb.listDevices();
    final device = devices
        .where(
          (d) =>
              d.isOnline &&
              (d.id == id ||
                  serial != null &&
                      (d.id == serial ||
                          _environment?.serials[d.id] == serial)),
        )
        .firstOrNull;
    if (device == null ||
        device.isIos ||
        device.isHarmony ||
        device.isShared ||
        !RegExp(r'^\d+$').hasMatch(device.transportId ?? '')) {
      throw StateError('Device is not available for sharing');
    }
    return device;
  }

  Future<String> _serial(DiscoveredDevice device, String? known) async {
    if (known != null && known.isNotEmpty && known != '-') return known;
    if (!device.id.contains(':') && !device.id.startsWith('adb-')) {
      return device.id;
    }
    final result = await adb.shellArgs(device.id, ['getprop', 'ro.serialno']);
    final serial = result.isSuccess ? result.stdout.trim() : '';
    return serial.isNotEmpty && serial != 'unknown' ? serial : device.id;
  }

  Future<void> _verifyIdentity(DiscoveredDevice device, String expected) async {
    if (device.id == expected &&
        !device.id.contains(':') &&
        !device.id.startsWith('adb-')) {
      return;
    }
    final result = await adb.shellArgs(device.id, ['getprop', 'ro.serialno']);
    if (!result.isSuccess || result.stdout.trim() != expected) {
      throw StateError('Shared source identity changed');
    }
  }

  Future<HostedDeviceShare> _startProfile(
    SavedDeviceShare profile,
    DiscoveredDevice device,
    String host, {
    DateTime? expiresAt,
  }) async {
    final share = await HostedDeviceShare.start(
      deviceId: device.id,
      backend:
          backendFactory?.call(device, profile.name) ??
          SharedAdbBackend(
            transportId: device.transportId!,
            name: profile.name,
          ),
      host: host,
      bindAddress: InternetAddress(host),
      identity: profile.identity,
      token: profile.token,
      resumable: true,
      lifetime: profile.lifetime.duration,
      expiresAt: expiresAt,
      onChanged: _notify,
    );
    if (_disposed) {
      await share.close();
      throw StateError('Sharing stopped');
    }
    try {
      final updated = profile.copyWith(
        deviceId: device.id,
        lastHost: host,
        lastPort: share.invitation.port,
      );
      await _save(
        profiles: [for (final p in profiles) p.id == profile.id ? updated : p],
      );
      if (_disposed) throw StateError('Sharing stopped');
      _hosts.add(share);
      _notify();
      return share;
    } catch (_) {
      await share.close();
      rethrow;
    }
  }

  /// 手动重新准备共享创建新的时间窗口，历史接收者仍使用原身份认证。
  Future<HostedDeviceShare> resumeShare(String id, {String? host}) =>
      _operate(() async {
        final profile = profiles.firstWhere((p) => p.id == id);
        final device = await _device(profile.deviceId, serial: profile.serial);
        await _verifyIdentity(device, profile.serial);
        final updated = profile.copyWith(enabled: true);
        await _save(
          profiles: [for (final p in profiles) p.id == id ? updated : p],
        );
        final existing = hosts
            .where((h) => h.invitation.fingerprint == id)
            .firstOrNull;
        await existing?.close();
        _automatic.reset(id);
        final share = await _startProfile(
          updated,
          device,
          host ?? profile.lastHost!,
        );
        _automatic.remember(updated, share);
        return share;
      });

  /// 手动停止同时暂停自动规则，避免状态通知把用户刚停止的共享立即重开。
  Future<void> stopShare(String id) => _operate(() async {
    final profile = profiles.firstWhere((p) => p.id == id);
    _profiles = [
      for (final p in profiles)
        p.id == id ? profile.copyWith(enabled: false) : p,
    ];
    final active = hosts
        .where((h) => h.invitation.fingerprint == id)
        .firstOrNull;
    await active?.close();
    await _save();
  });

  /// 删除规则销毁持久身份，旧分享码无法访问以后重新创建的共享。
  Future<void> forgetShare(String id) => _operate(() async {
    final active = hosts
        .where((h) => h.invitation.fingerprint == id)
        .firstOrNull;
    await active?.close();
    await _save(profiles: profiles.where((p) => p.id != id).toList());
    _automatic.reset(id);
  });

  Future<JoinedDeviceShare> join(String code) =>
      _operate(() => _join(DeviceShareInvitation.parse(code)));

  Future<JoinedDeviceShare> reconnect(String id) => _operate(() async {
    final invitation = history.firstWhere((h) => h.id == id).invitation;
    DeviceShareInvitation? current;
    try {
      current = await discovery?.find(invitation);
    } catch (_) {}
    return _join(current ?? invitation);
  });

  Future<JoinedDeviceShare> _join(DeviceShareInvitation invitation) async {
    if (profiles.any((p) => p.id == invitation.fingerprint) ||
        joins.any((j) => j.invitation.fingerprint == invitation.fingerprint)) {
      throw StateError('Shared device is already connected');
    }
    final joined = await JoinedDeviceShare.connect(invitation, adb, _notify);
    try {
      if (_disposed || joined.closed) throw StateError('Sharing stopped');
      await _save(
        history: [
          DeviceShareHistoryEntry(joined.invitation, now().toUtc()),
          ...history.where((h) => h.id != invitation.fingerprint),
        ].take(50).toList(),
      );
      if (_disposed || joined.closed) throw StateError('Sharing stopped');
      _joins.add(joined);
      _notify();
      return joined;
    } catch (_) {
      await joined.close();
      rethrow;
    }
  }

  Future<void> forgetHistory(String id) => _operate(() async {
    final joined = joins
        .where((j) => j.invitation.fingerprint == id)
        .firstOrNull;
    await joined?.close();
    await _save(history: history.where((h) => h.id != id).toList());
  });

  Future<void> updateEnvironment(DeviceShareEnvironment environment) {
    _environment = environment;
    validateHosts(environment.devices);
    return _automatic.update(environment);
  }

  /// 每次会话固定 transport，自动准备只能另建已确认物理身份的新会话。
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
    await _initializing?.catchError((Object _, StackTrace _) {});
    await _automatic.dispose();
    await _operation;
    await Future.wait([
      ...hosts.map((h) => h.close()),
      ...joins.map((j) => j.close()),
    ]);
    await discovery?.close();
    await _changes.close();
  }
}
