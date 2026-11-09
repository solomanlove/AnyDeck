import 'dart:async';
import 'dart:io';

import 'adb/shared_adb_backend.dart';
import 'adb/shared_adb_peer.dart';
import 'device_share_invitation.dart';
import 'share_socket_reader.dart';
import 'share_tls_identity.dart';

/// 分享方会话：一台设备允许一个接收端，停止时立即销毁已有 Socket。
class HostedDeviceShare {
  HostedDeviceShare._(
    this.deviceId,
    this.backend,
    this.invitation,
    this._server,
    this._context,
    this._onChanged,
  ) {
    _server.listen(
      _accept,
      onError: (_) {
        unawaited(close());
      },
    );
    if (invitation.expiresAt case final deadline?) {
      _expiry = Timer(deadline.difference(DateTime.now()), () {
        unawaited(close());
      });
    }
  }

  final String deviceId;
  final SharedAdbBackend backend;
  final DeviceShareInvitation invitation;
  final ServerSocket _server;
  final SecurityContext _context;
  final void Function() _onChanged;
  final _sockets = <Socket>{};
  SharedAdbPeer? _peer;
  bool _claimed = false;
  bool closed = false;
  Future<void>? _closing;
  Timer? _expiry;
  String? receiver;
  bool get connected => _claimed;

  static Future<HostedDeviceShare> start({
    required String deviceId,
    required SharedAdbBackend backend,
    required String host,
    required void Function() onChanged,
    ShareTlsIdentity? identity,
    InternetAddress? bindAddress,
    Duration? lifetime = const Duration(minutes: 30),
    DateTime? expiresAt,
    String? token,
    bool resumable = false,
    int port = 0,
  }) async {
    final address = InternetAddress.tryParse(host);
    if (address == null ||
        address.type != InternetAddressType.IPv4 ||
        address.rawAddress[0] == 0 ||
        address.rawAddress[0] >= 224 ||
        backend.name.length > 120) {
      throw const FormatException('Invalid share address or device name');
    }
    await backend.banner();
    final tls = identity ?? await ShareTlsIdentity.generate();
    final context = tls.createContext();
    final deadline =
        expiresAt ?? (lifetime == null ? null : DateTime.now().add(lifetime));
    if (deadline != null && !deadline.isAfter(DateTime.now())) {
      throw StateError('Sharing period has expired');
    }
    final server = await ServerSocket.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      port,
    );
    return HostedDeviceShare._(
      deviceId,
      backend,
      DeviceShareInvitation(
        host: host,
        port: server.port,
        fingerprint: tls.fingerprint,
        token: token ?? DeviceShareInvitation.createToken(),
        name: backend.name,
        resumable: resumable,
        expiresAt: deadline?.toUtc(),
      ),
      server,
      context,
      onChanged,
    );
  }

  bool _matchesToken(Object? input) {
    if (input is! String || input.length != invitation.token.length) {
      return false;
    }
    var difference = 0;
    for (var i = 0; i < input.length; i++) {
      difference |= input.codeUnitAt(i) ^ invitation.token.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<void> _accept(Socket raw) async {
    if (closed || _sockets.length >= 8) {
      raw.destroy();
      return;
    }
    final remoteAddress = raw.remoteAddress.address;
    _sockets.add(raw);
    SecureSocket? secure;
    ShareSocketReader? reader;
    var claimed = false;
    try {
      secure = await SecureSocket.secureServer(
        raw,
        _context,
      ).timeout(const Duration(seconds: 10));
      if (closed) return;
      _sockets.add(secure);
      secure.setOption(SocketOption.tcpNoDelay, true);
      reader = ShareSocketReader(secure);
      final auth = await reader.readMessage().timeout(
        const Duration(seconds: 10),
      );
      if (closed || auth['v'] != 1 || !_matchesToken(auth['key']) || _claimed) {
        await writeShareMessage(secure, {'ok': false});
        await secure.close();
        return;
      }
      _claimed = claimed = true;
      receiver = remoteAddress;
      _onChanged();
      await writeShareMessage(secure, {
        'ok': true,
        'name': backend.name,
        'expiresAt': invitation.expiresAt?.toIso8601String(),
      });
      final peer = SharedAdbPeer(secure, reader, backend);
      _peer = peer;
      await peer.run();
    } catch (_) {
      // 对端错误不得泄露分享令牌；连接状态由 finally 统一回收。
    } finally {
      raw.destroy();
      secure?.destroy();
      if (reader != null) unawaited(reader.cancel());
      _sockets.remove(raw);
      _sockets.remove(secure);
      if (claimed) {
        _peer = null;
        _claimed = false;
        receiver = null;
        _onChanged();
      }
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    closed = true;
    final peer = _peer;
    _expiry?.cancel();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    _sockets.clear();
    await _server.close();
    await peer?.close();
    _claimed = false;
    _onChanged();
  }
}
