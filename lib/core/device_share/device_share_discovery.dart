import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'device_share_invitation.dart';

/// 仅定位已知证书身份，UDP 中不发送分享令牌、私钥或设备列表。
abstract class DeviceShareDiscovery {
  Future<void> publish(List<DeviceShareInvitation> invitations);
  Future<DeviceShareInvitation?> find(DeviceShareInvitation invitation);
  Future<void> close();
}

/// 有界的局域网查找；发现结果仍须通过原有 TLS 指纹和分享令牌认证。
class UdpDeviceShareDiscovery implements DeviceShareDiscovery {
  /// [loopbackOnly] 将监听和查找限制在本机回环网络。
  UdpDeviceShareDiscovery({this.port = 52847, this.loopbackOnly = false});
  final int port;
  final bool loopbackOnly;
  InternetAddress get _bindAddress =>
      loopbackOnly ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4;
  static final _group = InternetAddress('239.255.88.21');
  static const _protocol = 'anydeck-device-share';
  final _advertisements = <String, DeviceShareInvitation>{};
  final _searches = <RawDatagramSocket>{};
  RawDatagramSocket? _listener;
  Future<void>? _listenerDone;
  Future<void>? _starting;
  bool _closed = false;
  int _replies = 0;
  DateTime _replyWindow = DateTime.now();

  @override
  Future<void> publish(List<DeviceShareInvitation> invitations) async {
    if (_closed) return;
    _advertisements
      ..clear()
      ..addEntries(
        invitations
            .where((entry) => entry.resumable)
            .map((entry) => MapEntry(entry.fingerprint, entry)),
      );
    if (_advertisements.isEmpty) {
      final closing = _listenerDone;
      _listener?.close();
      _listener = null;
      await _starting;
      // 只等待本次关闭的监听；后续 publish 可能已创建新的活动监听。
      await closing;
      return;
    }
    if (_listener == null) {
      await (_starting ??= _start().whenComplete(() => _starting = null));
    }
  }

  Future<void> _start() async {
    await _listenerDone;
    final socket = await RawDatagramSocket.bind(
      _bindAddress,
      port,
      reuseAddress: true,
    );
    socket.writeEventsEnabled = false;
    if (_closed || _advertisements.isEmpty) {
      // RawDatagramSocket 的接口 close() 不可等待，done 才表示端口已释放。
      final closed = socket.drain<void>();
      socket.close();
      await closed;
      return;
    }
    _listener = socket;
    final closed = Completer<void>();
    _listenerDone = closed.future;
    // 分别加入可用网卡，VPN 或不支持 multicast 的网卡失败不影响单播/广播。
    List<NetworkInterface> interfaces;
    try {
      interfaces = loopbackOnly
          ? []
          : await NetworkInterface.list(type: InternetAddressType.IPv4);
    } catch (_) {
      interfaces = [];
    }
    for (final interface in interfaces) {
      try {
        socket.joinMulticast(_group, interface);
      } catch (_) {}
    }
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = socket.receive();
      if (packet == null || packet.data.length > 512) return;
      try {
        final request = jsonDecode(utf8.decode(packet.data)) as Map;
        if (request['protocol'] != _protocol ||
            request['v'] != 1 ||
            request['find'] is! String ||
            request['nonce'] is! String ||
            (request['nonce'] as String).length != 43) {
          return;
        }
        final invitation = _advertisements[request['find']];
        if (invitation == null ||
            (invitation.expiresAt != null &&
                !invitation.expiresAt!.isAfter(DateTime.now()))) {
          return;
        }
        if (DateTime.now().difference(_replyWindow).inSeconds >= 1) {
          _replyWindow = DateTime.now();
          _replies = 0;
        }
        if (++_replies > 20) return;
        socket.send(
          utf8.encode(
            jsonEncode({
              'protocol': _protocol,
              'v': 1,
              'fp': invitation.fingerprint,
              'nonce': request['nonce'],
              'port': invitation.port,
            }),
          ),
          packet.address,
          packet.port,
        );
      } catch (_) {
        /* 无效或未知 UDP 数据不影响共享会话。 */
      }
    }, onError: (_) {}, onDone: closed.complete);
  }

  @override
  Future<DeviceShareInvitation?> find(DeviceShareInvitation invitation) async {
    if (_closed || !invitation.resumable) return null;
    final socket = await RawDatagramSocket.bind(_bindAddress, 0);
    _searches.add(socket);
    socket.writeEventsEnabled = false;
    if (!loopbackOnly) {
      socket
        ..broadcastEnabled = true
        ..multicastHops = 1;
    }
    final result = Completer<DeviceShareInvitation?>();
    final nonce = DeviceShareInvitation.createToken();
    final request = utf8.encode(
      jsonEncode({
        'protocol': _protocol,
        'v': 1,
        'find': invitation.fingerprint,
        'nonce': nonce,
      }),
    );
    final subscription = socket.listen(
      (event) {
        if (event != RawSocketEvent.read || result.isCompleted) return;
        final packet = socket.receive();
        if (packet == null || packet.data.length > 512) return;
        try {
          final reply = jsonDecode(utf8.decode(packet.data)) as Map;
          final targetPort = reply['port'];
          if (reply['protocol'] == _protocol &&
              reply['v'] == 1 &&
              reply['fp'] == invitation.fingerprint &&
              reply['nonce'] == nonce &&
              targetPort is int &&
              targetPort > 0 &&
              targetPort <= 65535 &&
              packet.address.type == InternetAddressType.IPv4 &&
              !packet.address.isMulticast) {
            result.complete(invitation.at(packet.address.address, targetPort));
          }
        } catch (_) {}
      },
      onError: (_) {},
      onDone: () {
        if (!result.isCompleted) result.complete(null);
      },
    );
    void send() {
      for (final address in [
        if (loopbackOnly)
          InternetAddress.loopbackIPv4
        else ...[
          InternetAddress(invitation.host),
          InternetAddress('255.255.255.255'),
          _group,
        ],
      ]) {
        try {
          socket.send(request, address, port);
        } catch (_) {}
      }
    }

    final retry = Timer(const Duration(milliseconds: 400), send);
    final timeout = Timer(const Duration(milliseconds: 1200), () {
      if (!result.isCompleted) result.complete(null);
    });
    try {
      send();
      return await result.future;
    } finally {
      retry.cancel();
      timeout.cancel();
      socket.close();
      _searches.remove(socket);
      await subscription.cancel();
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _advertisements.clear();
    _listener?.close();
    _listener = null;
    for (final socket in _searches.toList()) {
      socket.close();
    }
    await _starting;
    await _listenerDone;
  }
}
