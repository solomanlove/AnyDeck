import 'dart:async';

import '../adb_device.dart';
import '../adb_service.dart';
import 'adb_wireless_probe.dart';
import 'adb_wireless_state.dart';

/// 主窗口无线连接编排：USB 自动准备、TCP 优先、目标 mDNS 回退。
/// 同设备合并请求，所有设备任务串行执行，避免重启风暴和并发 ADB 进程。
class AdbWirelessCoordinator {
  AdbWirelessCoordinator(
    AdbService adb, {
    required this.onState,
    this.restartDelay = const Duration(seconds: 2),
    this.readyTimeout = const Duration(seconds: 10),
    this.pollDelay = const Duration(milliseconds: 500),
    this.detachGrace = const Duration(seconds: 15),
  }) {
    probe = AdbWirelessProbe(adb, isCancelled: () => _disposed);
  }

  final void Function(AdbWirelessState) onState;
  final Duration restartDelay;
  final Duration readyTimeout;
  final Duration pollDelay;
  final Duration detachGrace;
  late final AdbWirelessProbe probe;
  final _jobs = <String, Future<AdbWirelessResult>>{};
  final _preparations = <String, Future<AdbWirelessResult>>{};
  final _seenUsb = <String>{};
  Set<String> _onlineUsb = {};
  final _detachTimers = <String, Timer>{};
  final _ips = <String, String>{};
  final _serials = <String, String>{};
  Future<void> _tail = Future.value();
  bool _disposed = false;

  /// 仅处理已授权的 Android 实体 USB；短暂重启离线不清除本次准备标记。
  void observe(List<AdbDevice> devices) {
    if (_disposed) return;
    final usb = devices.where(
      (d) => d.isOnline && !d.isIos && !d.isHarmony && isPhysicalUsbId(d.id),
    );
    final onlineIds = usb.map((d) => d.id).toSet();
    _onlineUsb = onlineIds;
    for (final id in _seenUsb.difference(onlineIds)) {
      _detachTimers.putIfAbsent(
        id,
        () => Timer(detachGrace, () {
          _detachTimers.remove(id);
          if (!_jobs.containsKey(id)) _seenUsb.remove(id);
        }),
      );
    }
    for (final device in usb) {
      _detachTimers.remove(device.id)?.cancel();
      if (_seenUsb.add(device.id)) unawaited(prepareUsb(device.id));
    }
  }

  void _emit(
    String key,
    String message, {
    bool busy = false,
    bool failed = false,
  }) {
    if (_disposed) return;
    onState(
      AdbWirelessState(
        deviceId: key,
        messageKey: message,
        busy: busy,
        failed: failed,
        ip: _ips[key],
        serial: _serials[key],
      ),
    );
  }

  Future<AdbWirelessResult> _schedule(
    String key,
    Future<AdbWirelessResult> Function() action,
  ) {
    if (_disposed) {
      return Future.value(const AdbWirelessResult('wirelessCancelled'));
    }
    final current = _jobs[key];
    if (current != null) return current;
    _emit(key, 'wirelessPreparing', busy: true);
    final job = _tail.then((_) async {
      if (_disposed) return const AdbWirelessResult('wirelessCancelled');
      try {
        return await action();
      } catch (error) {
        return AdbWirelessResult('wirelessFailed', detail: error.toString());
      }
    });
    _jobs[key] = job;
    _tail = job.then((result) {
      _jobs.remove(key);
      if (!_onlineUsb.contains(key) && !_detachTimers.containsKey(key)) {
        _seenUsb.remove(key);
      }
      _emit(key, result.messageKey, failed: !result.isSuccess);
    });
    return job;
  }

  Future<AdbWirelessResult> prepareUsb(String id) {
    _seenUsb.add(id);
    final existing = _preparations[id];
    if (existing != null) return existing;
    final job = _schedule(id, () => _prepareUsb(id));
    _preparations[id] = job;
    unawaited(job.then((_) => _preparations.remove(id)));
    return job;
  }

  /// 元数据探测等读取操作等待本机重启结束，不与 tcpip 重启竞争。
  Future<void> waitForPreparation(String id) async {
    await _preparations[id];
  }

  Future<AdbWirelessResult> _prepareUsb(String id) async {
    _ips.remove(id);
    if (!await probe.online(id)) {
      return const AdbWirelessResult('wirelessAuthorize');
    }
    _serials[id] = await probe.serial(id) ?? id;
    _emit(id, 'wirelessPreparing', busy: true);
    final enabled = await _enable(id);
    if (!enabled) return const AdbWirelessResult('wirelessEnableFailed');
    final watch = Stopwatch()..start();
    while (!_disposed && watch.elapsed < readyTimeout) {
      if (await probe.online(id, timeout: _remaining(watch))) {
        final ip = await probe.ip(id, remaining: () => _remaining(watch));
        if (ip != null) {
          _ips[id] = ip;
          return const AdbWirelessResult('wirelessReady', success: true);
        }
      }
      await Future<void>.delayed(pollDelay);
    }
    return const AdbWirelessResult('wirelessNoIp');
  }

  /// 已监听 5555 时跳过重启，避免插线或重新点击打断现有会话。
  Future<bool> _enable(String source) async {
    final port = await probe.run([
      '-s',
      source,
      'shell',
      'getprop',
      'service.adb.tcp.port',
    ]);
    if (port.isSuccess && port.stdout.trim() == '5555') return true;
    final result = await probe.run(['-s', source, 'tcpip', '5555']);
    if (!result.isSuccess) return false;
    await Future<void>.delayed(restartDelay);
    return !_disposed;
  }

  Duration _remaining(Stopwatch watch) {
    final remaining = readyTimeout - watch.elapsed;
    if (remaining <= Duration.zero) return Duration.zero;
    return remaining < const Duration(seconds: 2)
        ? remaining
        : const Duration(seconds: 2);
  }

  /// 点击连接时只使用目标设备身份；source 可为当前 USB/TLS 通道。
  Future<AdbWirelessResult> connect({
    required String key,
    String? serial,
    String? source,
    String? ip,
    List<String> connections = const [],
  }) async {
    // 等待自动准备完成后再连接，同期点击合并为一个连接任务。
    final preparing = _preparations[source];
    if (preparing != null) await preparing;
    return _schedule(key, () => _connect(key, serial, source, ip, connections));
  }

  Future<AdbWirelessResult> _connect(
    String key,
    String? serial,
    String? source,
    String? ip,
    List<String> connections,
  ) async {
    serial ??= _serials[source] ?? _serials[key];
    ip = wirelessIpv4(ip) ?? _ips[source] ?? _ips[key];
    if (source != null && await probe.online(source)) {
      final actual = await probe.serial(source);
      final usbFallback = serial == source && isPhysicalUsbId(source);
      if (actual == null ||
          (serial != null && actual != serial && !usbFallback)) {
        return const AdbWirelessResult('wirelessIdentityMismatch');
      }
      serial = actual;
      if (isPhysicalUsbId(source)) {
        await _prepareUsb(source);
        ip = _ips[source];
      } else {
        ip = await probe.ip(source) ?? ip;
      }
    }
    if (serial != null) _serials[key] = serial;
    if (ip != null) _ips[key] = ip;
    if (serial == null) {
      return const AdbWirelessResult('wirelessIdentityUnknown');
    }
    _emit(key, 'wirelessConnecting', busy: true);
    if (ip != null && await probe.connect('$ip:5555', serial)) {
      return _finishTcp(key, '$ip:5555', serial, connections);
    }
    _emit(key, 'wirelessDiscovering', busy: true);
    // 身份不明时不能只凭旧 IP 自动重启局域网中的另一部手机。
    if (source != null &&
        isWirelessTlsId(source) &&
        await probe.online(source)) {
      return _upgrade(key, source, serial, ip, connections);
    }
    for (var i = 0; i < 3 && !_disposed; i++) {
      final attempted = <String>{};
      final endpoints =
          (await probe.discover()).where((e) => e.matches(serial, ip)).toList()
            ..sort((a, b) => (a.isTls ? 1 : 0).compareTo(b.isTls ? 1 : 0));
      for (final endpoint in endpoints) {
        if (!attempted.add(endpoint.address)) continue;
        if (!await probe.connect(endpoint.address, serial)) continue;
        _ips[key] = endpoint.ip;
        if (!endpoint.isTls) {
          return _finishTcp(key, endpoint.address, serial, connections);
        }
        return _upgrade(key, endpoint.address, serial, endpoint.ip, [
          ...connections,
          endpoint.address,
          '${endpoint.name}.${endpoint.type}',
        ]);
      }
      if (i < 2) await Future<void>.delayed(const Duration(seconds: 1));
    }
    // 兜底校验：检查目标设备在此期间是否已成功接入 TCP 5555
    if (ip != null && await probe.online('$ip:5555')) {
      final actual = await probe.serial('$ip:5555');
      if (actual == null || actual == serial) {
        return _finishTcp(key, '$ip:5555', serial, connections);
      }
    }
    return const AdbWirelessResult('wirelessUnavailable');
  }

  Future<AdbWirelessResult> _upgrade(
    String key,
    String source,
    String serial,
    String? ip,
    List<String> connections,
  ) async {
    // 必须在重启 adbd 前保存地址，TLS 通道可能立即消失。
    ip = await probe.ip(source) ?? ip;
    if (ip == null) {
      return const AdbWirelessResult('wirelessTlsFallback', success: true);
    }
    _ips[key] = ip;
    _emit(key, 'wirelessSwitching', busy: true);
    if (await _enable(source)) {
      final watch = Stopwatch()..start();
      while (!_disposed && watch.elapsed < readyTimeout) {
        final address = '$ip:5555';
        await probe.run(['connect', address], timeout: _remaining(watch));
        if (watch.elapsed < readyTimeout &&
            await probe.online(address, timeout: _remaining(watch)) &&
            await probe.serial(address, remaining: () => _remaining(watch)) ==
                serial) {
          return _finishTcp(key, address, serial, [...connections, source]);
        }
        await Future<void>.delayed(pollDelay);
      }
    }
    // 切换失败时恢复已授权 TLS；重启后的动态端口可能已改变。
    if (await probe.connect(source, serial)) {
      return const AdbWirelessResult('wirelessTlsFallback', success: true);
    }
    for (final endpoint in await probe.discover()) {
      if (endpoint.isTls &&
          endpoint.matches(serial, ip) &&
          await probe.connect(endpoint.address, serial)) {
        _ips[key] = endpoint.ip;
        return const AdbWirelessResult('wirelessTlsFallback', success: true);
      }
    }
    return const AdbWirelessResult('wirelessSwitchFailed');
  }

  Future<AdbWirelessResult> _finishTcp(
    String key,
    String address,
    String? serial,
    List<String> connections,
  ) async {
    final fresh = await probe.ip(address);
    if (fresh != null) _ips[key] = fresh;
    // 只断开同一手机的 TLS transport；不关闭手机设置或修改共享 ADB Server。
    for (final id in connections.toSet()) {
      if (id != address &&
          isWirelessTlsId(id) &&
          serial != null &&
          await probe.online(id) &&
          await probe.serial(id) == serial) {
        await probe.run(['disconnect', id]);
      }
    }
    return const AdbWirelessResult('wirelessConnected', success: true);
  }

  /// 配对后使用发现的 TLS 连接端口，绝不把配对端口当作连接端口。
  Future<AdbWirelessResult> pair(String address, String code) => _schedule(
    'pair:$address',
    () async {
      final result = await probe.run([
        'pair',
        address,
        code,
      ], timeout: const Duration(seconds: 15));
      final ip = wirelessIpv4(address.split(':').first);
      if (!result.isSuccess ||
          !result.stdout.contains('Successfully paired') ||
          ip == null) {
        return AdbWirelessResult('wirelessPairFailed', detail: result.message);
      }
      for (var i = 0; i < 5 && !_disposed; i++) {
        for (final endpoint in await probe.discover()) {
          if (!endpoint.isTls || endpoint.ip != ip) continue;
          if (!await probe.connect(endpoint.address, null)) continue;
          final serial = await probe.serial(endpoint.address);
          if (serial == null) continue;
          final connected = await _connect(
            serial,
            serial,
            endpoint.address,
            ip,
            [endpoint.address, '${endpoint.name}.${endpoint.type}'],
          );
          _emit(serial, connected.messageKey, failed: !connected.isSuccess);
          return connected;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      return const AdbWirelessResult('wirelessPairedNoService');
    },
  );

  void dispose() {
    _disposed = true;
    for (final timer in _detachTimers.values) {
      timer.cancel();
    }
    _detachTimers.clear();
  }
}
