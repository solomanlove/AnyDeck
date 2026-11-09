import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/core/device_share/adb/adb_packet.dart';
import 'package:any_deck/core/device_share/adb/shared_adb_backend.dart';
import 'package:any_deck/core/device_share/device_share_invitation.dart';
import 'package:any_deck/core/device_share/hosted_device_share.dart';
import 'package:any_deck/core/device_share/share_socket_reader.dart';

/// 真正使用 loopback Socket 的 Smart Socket 桩，不连接 USB 或真实手机。
class ShareAdbFixture {
  late final ServerSocket server;
  final sockets = <Socket>{};
  final requests = <String>[];
  final reversePorts = <String, int>{};
  String transportId = '72';
  Completer<void>? reverseGate;
  String features = 'shell_v2,stat_v2,sendrecv_v2,delayed_ack';
  // 模拟设备服务尚未建立，不能阻塞其他 Stream 的 ACK 或 OPEN。
  Future<void> Function(String)? beforeServiceReply;
  Future<void> Function(String, Socket, ShareSocketReader)? onService;

  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_accept);
  }

  Future<String> _request(ShareSocketReader reader) async {
    final length = int.parse(ascii.decode(await reader.read(4)), radix: 16);
    final value = utf8.decode(await reader.read(length));
    requests.add(value);
    return value;
  }

  Future<void> _accept(Socket socket) async {
    sockets.add(socket);
    final reader = ShareSocketReader(socket);
    try {
      final request = await _request(reader);
      if (request == 'host-transport-id:$transportId:features') {
        socket.write(
          'OKAY${features.length.toRadixString(16).padLeft(4, '0')}$features',
        );
      } else if (request == 'host:transport-id:$transportId') {
        socket.write('OKAY');
        await socket.flush();
        final service = await _request(reader);
        await beforeServiceReply?.call(service);
        socket.write('OKAY');
        await socket.flush();
        if (service.startsWith('reverse:forward:norebind:')) {
          await reverseGate?.future;
          final match = RegExp(r'tcp:(\d+);tcp:(\d+)$').firstMatch(service)!;
          final devicePort = match[1] == '0' ? '43000' : match[1]!;
          final key = 'tcp:$devicePort';
          if (reversePorts.containsKey(key)) {
            socket.write('FAIL0004busy');
          } else {
            reversePorts[key] = int.parse(match[2]!);
            socket.write(match[1] == '0' ? 'OKAY000543000' : 'OKAY');
          }
        } else if (service.startsWith('reverse:killforward:')) {
          reversePorts.remove(service.substring('reverse:killforward:'.length));
          socket.write('OKAY');
        } else if (onService != null) {
          await onService!(service, socket, reader);
        } else {
          socket.add(utf8.encode('hello from shared phone\n'));
        }
      } else {
        socket.write('FAIL0007unknown');
      }
      await socket.flush();
      await socket.close();
    } catch (_) {
      socket.destroy();
    } finally {
      sockets.remove(socket);
      unawaited(reader.cancel());
    }
  }

  SharedAdbBackend get backend => SharedAdbBackend(
    transportId: transportId,
    name: 'AnyDeck test phone',
    port: server.port,
  );

  Future<void> close() async {
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    await server.close();
  }
}

/// 接收端 Transport 测试客户端；分享认证与 ADB 握手分别执行以验证边界。
class ShareClientFixture {
  ShareClientFixture(this.socket) : reader = ShareSocketReader(socket);
  final SecureSocket socket;
  final ShareSocketReader reader;

  static Future<ShareClientFixture> connect(
    HostedDeviceShare host, {
    String? token,
  }) async {
    final socket = await SecureSocket.connect(
      '127.0.0.1',
      host.invitation.port,
      onBadCertificate: (_) => true,
    );
    final client = ShareClientFixture(socket);
    await writeShareMessage(socket, {
      'v': 1,
      'key': token ?? host.invitation.token,
    });
    return client;
  }

  Future<Map<String, dynamic>> auth() => reader.readMessage();
  Future<void> send(int command, int arg0, int arg1, [List<int>? data]) async {
    socket.add(
      AdbPacket(
        command,
        arg0,
        arg1,
        data == null ? null : Uint8List.fromList(data),
      ).encode(),
    );
    await socket.flush();
  }

  Future<AdbPacket> handshake({int payload = 4096}) async {
    await send(
      AdbPacket.cnxn,
      0x01000001,
      payload,
      utf8.encode('host::\u0000'),
    );
    return packet();
  }

  Future<AdbPacket> packet() =>
      AdbPacket.read(reader).timeout(const Duration(seconds: 5));
  Future<void> open(String service, [int id = 1]) =>
      send(AdbPacket.open, id, 0, utf8.encode('$service\u0000'));
  Future<void> close() async {
    socket.destroy();
    await reader.cancel();
  }
}

DeviceShareInvitation replaceInvitation(
  DeviceShareInvitation source, {
  String? fingerprint,
  String? token,
}) => DeviceShareInvitation(
  host: source.host,
  port: source.port,
  fingerprint: fingerprint ?? source.fingerprint,
  token: token ?? source.token,
  name: source.name,
);
