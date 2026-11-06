import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../adb/adb_service.dart';
import 'device_share_invitation.dart';
import 'share_socket_reader.dart';

/// 接收端只向回环地址导出 Transport，本机 ADB 继续管理本地和共享设备。
class JoinedDeviceShare {
  JoinedDeviceShare._(
    this.invitation,
    this._adb,
    this._server,
    this._secure,
    this._reader,
    this._onClosed,
  ) : _port = _server.port {
    _server.listen(
      _accept,
      onError: (_) {
        unawaited(close());
      },
    );
  }
  final DeviceShareInvitation invitation;
  final AdbService _adb;
  final ServerSocket _server;
  final int _port;
  final SecureSocket _secure;
  final ShareSocketReader _reader;
  final void Function() _onClosed;
  Socket? _local;
  bool closed = false;
  Future<void>? _closing;
  String get deviceId => '127.0.0.1:$_port';

  static Future<JoinedDeviceShare> connect(
    DeviceShareInvitation invitation,
    AdbService adb,
    void Function() onClosed,
  ) async {
    final secure = await SecureSocket.connect(
      invitation.host,
      invitation.port,
      context: SecurityContext(withTrustedRoots: false),
      onBadCertificate: (certificate) =>
          sha256.convert(certificate.der).toString() == invitation.fingerprint,
      timeout: const Duration(seconds: 10),
    );
    final reader = ShareSocketReader(secure);
    ServerSocket? server;
    JoinedDeviceShare? joined;
    try {
      final certificate = secure.peerCertificate;
      if (certificate == null ||
          sha256.convert(certificate.der).toString() !=
              invitation.fingerprint) {
        throw const HandshakeException('Share certificate mismatch');
      }
      secure.setOption(SocketOption.tcpNoDelay, true);
      await writeShareMessage(secure, {'v': 1, 'key': invitation.token});
      final response = await reader.readMessage().timeout(
        const Duration(seconds: 10),
      );
      if (response['ok'] != true) {
        throw const SocketException('Share unavailable or in use');
      }
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      joined = JoinedDeviceShare._(
        invitation,
        adb,
        server,
        secure,
        reader,
        onClosed,
      );
      final connected = await adb.run(['connect', joined.deviceId]);
      if (!connected.isSuccess || joined.closed) {
        throw const SocketException('ADB share connection failed');
      }
      final state = await adb.run(['-s', joined.deviceId, 'get-state']);
      if (!state.isSuccess ||
          state.stdout.trim() != 'device' ||
          joined.closed) {
        throw const SocketException('Shared device is offline');
      }
      return joined;
    } catch (_) {
      if (joined != null) {
        await joined.close();
      } else {
        secure.destroy();
        unawaited(reader.cancel());
        await server?.close();
      }
      rethrow;
    }
  }

  Future<void> _accept(Socket local) async {
    if (closed || _local != null) {
      local.destroy();
      return;
    }
    _local = local;
    local.setOption(SocketOption.tcpNoDelay, true);
    final input = ShareSocketReader(local);
    Future<void> relay(ShareSocketReader source, Socket target) async {
      while (!closed) {
        final chunk = await source.readChunk();
        if (chunk == null) break;
        target.add(chunk);
        await target.flush().timeout(const Duration(seconds: 15));
      }
    }

    try {
      await Future.any([relay(input, _secure), relay(_reader, local)]);
    } catch (_) {
      // 任意方向断开都使本次共享失效，禁止静默重连已经撤销的会话。
    } finally {
      unawaited(input.cancel());
      await close();
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    closed = true;
    final id = deviceId;
    _secure.destroy();
    _local?.destroy();
    unawaited(_reader.cancel());
    await _server.close();
    _onClosed();
    await _adb.run(['disconnect', id], timeout: const Duration(seconds: 5));
  }
}
