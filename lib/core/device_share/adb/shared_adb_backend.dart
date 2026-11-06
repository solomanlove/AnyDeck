import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../share_socket_reader.dart';

/// 一个已选定 transport 的服务流，读写保持二进制原样。
class SharedAdbConnection {
  SharedAdbConnection(this.socket, this.reader);
  final Socket socket;
  final ShareSocketReader reader;
  void close() {
    socket.destroy();
    unawaited(reader.cancel());
  }
}

/// 宿主 ADB Smart Socket 客户端：每条流固定 transport ID，禁止切换设备。
class SharedAdbBackend {
  SharedAdbBackend({
    required this.transportId,
    required this.name,
    this.host = '127.0.0.1',
    this.port = 5037,
  });
  final String transportId, name, host;
  final int port;
  static const timeout = Duration(seconds: 5);

  Future<SharedAdbConnection> _connect() async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return SharedAdbConnection(socket, ShareSocketReader(socket));
  }

  Future<void> _request(SharedAdbConnection connection, String request) async {
    final bytes = utf8.encode(request);
    connection.socket.add(
      ascii.encode(bytes.length.toRadixString(16).padLeft(4, '0')),
    );
    connection.socket.add(bytes);
    await connection.socket.flush();
    final status = ascii.decode(await connection.reader.read(4));
    if (status != 'OKAY') {
      throw const SocketException('ADB rejected shared device service');
    }
  }

  Future<SharedAdbConnection> open(String service) async {
    final connection = await _connect();
    try {
      await (() async {
        await _request(connection, 'host:transport-id:$transportId');
        await _request(connection, service);
      })().timeout(timeout);
      return connection;
    } catch (_) {
      connection.close();
      rethrow;
    }
  }

  /// 只宣告已验证可透明转发的设备能力；不宣告 delayed_ack。
  Future<String> banner() async {
    final connection = await _connect();
    try {
      final features = await (() async {
        await _request(connection, 'host-transport-id:$transportId:features');
        final length = int.parse(
          ascii.decode(await connection.reader.read(4)),
          radix: 16,
        );
        if (length > 4096) throw const FormatException('Invalid ADB features');
        return utf8.decode(await connection.reader.read(length)).split(',');
      })().timeout(timeout);
      const supported = {
        'shell_v2',
        'cmd',
        'stat_v2',
        'ls_v2',
        'fixed_push_mkdir',
        'apex',
        'abb',
        'abb_exec',
        'sendrecv_v2',
        'sendrecv_v2_brotli',
        'sendrecv_v2_lz4',
        'sendrecv_v2_zstd',
        'sendrecv_v2_dry_run_send',
        'track_app',
      };
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      return 'device::ro.product.name=anydeck_shared_device;'
          'ro.product.model=$safeName;ro.product.device=anydeck_shared;'
          'features=${features.where(supported.contains).join(',')};\u0000';
    } finally {
      connection.close();
    }
  }

  /// Reverse 的返回值属于设备服务协议，保持 OKAY/FAIL 格式并限制结果长度。
  Future<Uint8List> reverse(String service) async {
    final connection = await open(service);
    try {
      return await (() async {
        final bytes = BytesBuilder();
        while (true) {
          final chunk = await connection.reader.readChunk(4096);
          if (chunk == null) return bytes.takeBytes();
          bytes.add(chunk);
          if (bytes.length > 65536) {
            throw const FormatException('Invalid reverse reply');
          }
        }
      })().timeout(timeout);
    } finally {
      connection.close();
    }
  }
}
