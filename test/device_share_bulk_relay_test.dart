import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/core/device_share/adb/adb_packet.dart';
import 'package:any_deck/core/device_share/adb/shared_adb_bulk_relay.dart';
import 'package:any_deck/core/device_share/share_socket_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实 loopback Socket 的两端，支持精确控制每一块 Legacy ADB ACK。
class _Pair {
  _Pair(this.peer, this.bridge)
    : peerReader = ShareSocketReader(peer),
      bridgeReader = ShareSocketReader(bridge);
  final Socket peer, bridge;
  final ShareSocketReader peerReader, bridgeReader;

  static Future<_Pair> create() async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepting = listener.first;
    final peer = await Socket.connect(
      InternetAddress.loopbackIPv4,
      listener.port,
    );
    final bridge = await accepting;
    await listener.close();
    return _Pair(peer, bridge);
  }

  Future<void> send(int command, int arg0, int arg1, [List<int>? bytes]) async {
    peer.add(
      AdbPacket(
        command,
        arg0,
        arg1,
        bytes == null ? null : Uint8List.fromList(bytes),
      ).encode(),
    );
    await peer.flush();
  }

  Future<AdbPacket> packet() =>
      AdbPacket.read(peerReader).timeout(const Duration(seconds: 2));

  Future<void> close() async {
    peer.destroy();
    bridge.destroy();
    await peerReader.cancel();
    await bridgeReader.cancel();
  }
}

/// 只挂起出口 flush，让对端先关闭已经排队但尚未写入的聚合 payload。
class _GatedSocket implements Socket {
  _GatedSocket(this.socket);
  final Socket socket;
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  void add(List<int> data) => socket.add(data);
  @override
  Future<void> flush() async {
    await socket.flush();
    if (gate != null) {
      if (!entered.isCompleted) entered.complete();
      await gate!.future;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Pair local, remote;
  late _GatedSocket writer, localWriter;
  late SharedAdbBulkRelay relay;
  late Future<void> running;
  late List<String> diagnostics;
  var negotiated = false;

  setUp(() async {
    local = await _Pair.create();
    remote = await _Pair.create();
    writer = _GatedSocket(remote.bridge);
    localWriter = _GatedSocket(local.bridge);
    diagnostics = [];
    negotiated = false;
    relay = SharedAdbBulkRelay(
      localSocket: localWriter,
      localReader: local.bridgeReader,
      remoteSocket: writer,
      remoteReader: remote.bridgeReader,
      onDiagnostic: diagnostics.add,
    );
    running = relay.run().catchError((_) {});
  });
  tearDown(() async {
    relay.close();
    if (writer.gate case final gate? when !gate.isCompleted) gate.complete();
    if (localWriter.gate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    await local.close();
    await remote.close();
    await running;
  });

  Future<void> negotiate([int limit = 16384]) async {
    if (negotiated) return;
    negotiated = true;
    await local.send(AdbPacket.cnxn, 0x01000001, limit);
    expect((await remote.packet()).command, AdbPacket.cnxn);
    await remote.send(AdbPacket.cnxn, 0x01000001, limit);
    expect((await local.packet()).command, AdbPacket.cnxn);
  }

  Future<void> open(String service, int id) async {
    await negotiate();
    await local.send(AdbPacket.open, id, 0, utf8.encode('$service\u0000'));
    final request = await remote.packet();
    expect(request.data, utf8.encode('$service\u0000'));
    await remote.send(AdbPacket.okay, id + 100, id);
    final opened = await local.packet();
    expect(
      (opened.command, opened.arg0, opened.arg1),
      (AdbPacket.okay, id + 100, id),
    );
  }

  Future<void> write(int id, int byte, [int size = 4096]) =>
      local.send(AdbPacket.wrte, id, id + 100, List.filled(size, byte));

  Future<void> expectAck(int id) async {
    final ack = await local.packet();
    expect((ack.command, ack.arg0, ack.arg1), (AdbPacket.okay, id + 100, id));
  }

  test('远端 ACK 未到时本地继续有界发送，后续积压合并且 hash 不变', () async {
    await open('abb:package\u0000install-write', 1);
    await write(1, 1);
    final first = await remote.packet();
    expect(first.data, List.filled(4096, 1));
    await expectAck(1);
    for (var i = 2; i <= 3; i++) {
      await write(1, i);
      await expectAck(1);
    }
    await write(1, 4);
    // 已发+待发达到窗口上限，第四块的本地 ACK 必须等远端腾出空间。
    await remote.send(AdbPacket.wrte, 900, 901, [88]);
    expect((await local.packet()).command, AdbPacket.wrte);
    await remote.send(AdbPacket.okay, 101, 1);
    final batch = await remote.packet();
    expect(batch.data.length, 12288);
    expect(
      sha256.convert(batch.data),
      sha256.convert([
        ...List.filled(4096, 2),
        ...List.filled(4096, 3),
        ...List.filled(4096, 4),
      ]),
    );
    await expectAck(1);
    await remote.send(AdbPacket.okay, 101, 1);
    // 聚合包只对应一个远端 ACK，不能重复发布三个已经提前完成的本地 ACK。
    await remote.send(AdbPacket.wrte, 900, 901, [99]);
    expect((await local.packet()).data, [99]);
  });

  test('本地关闭不会越过已经确认但还在等待的上传字节', () async {
    await open('sync:', 1);
    await write(1, 1);
    expect((await remote.packet()).data.length, 4096);
    await expectAck(1);
    await write(1, 2);
    await expectAck(1);
    await write(1, 3);
    await expectAck(1);
    await local.send(AdbPacket.clse, 1, 101);
    await remote.send(AdbPacket.okay, 101, 1);
    final pending = await remote.packet();
    expect(pending.command, AdbPacket.wrte);
    expect(pending.data, [...List.filled(4096, 2), ...List.filled(4096, 3)]);
    await remote.send(AdbPacket.okay, 101, 1);
    expect((await remote.packet()).command, AdbPacket.clse);
    await remote.send(AdbPacket.clse, 101, 1);
    expect((await local.packet()).command, AdbPacket.clse);
  });

  test('远端关闭会取消排队的聚合 WRTE，不再向已关闭服务发布输入', () async {
    await open('abb_exec:package\u0000install', 1);
    await write(1, 1);
    await remote.packet();
    await expectAck(1);
    await write(1, 2);
    await expectAck(1);
    writer.gate = Completer<void>();
    await local.send(AdbPacket.open, 2, 0, utf8.encode('shell:id\u0000'));
    expect((await remote.packet()).command, AdbPacket.open);
    await writer.entered.future;
    await remote.send(AdbPacket.okay, 101, 1);
    await remote.send(AdbPacket.clse, 101, 1);
    expect((await local.packet()).command, AdbPacket.clse);
    writer.gate!.complete();
    await remote.send(AdbPacket.okay, 102, 2);
    await expectAck(2);
    await local.send(AdbPacket.wrte, 2, 102, [42]);
    final next = await remote.packet();
    expect((next.command, next.arg0), (AdbPacket.wrte, 2));
    expect(next.data, [42]);
  });

  test('错误远端 ID 和重复 ACK 不会撤销当前上传或增加本地额度', () async {
    await open('sync:', 1);
    await write(1, 1);
    await remote.packet();
    await expectAck(1);
    await remote.send(AdbPacket.clse, 999, 1);
    await remote.send(AdbPacket.okay, 999, 1);
    await write(1, 2);
    await expectAck(1);
    await remote.send(AdbPacket.okay, 101, 1);
    expect((await remote.packet()).data, List.filled(4096, 2));
    await remote.send(AdbPacket.okay, 101, 1);
    await remote.send(AdbPacket.okay, 101, 1);
    await remote.send(AdbPacket.wrte, 900, 901, [88]);
    expect((await local.packet()).data, [88]);
  });

  test('最多四条 bulk 流提前确认，第五条及非 bulk 双向透明转发', () async {
    for (var id = 1; id <= 5; id++) {
      await open('sync:', id);
    }
    await write(5, 5);
    expect((await remote.packet()).arg0, 5);
    await remote.send(AdbPacket.wrte, 900, 901, [77]);
    expect((await local.packet()).command, AdbPacket.wrte);
    await remote.send(AdbPacket.okay, 105, 5);
    await expectAck(5);
    await open('shell:id', 6);
    await local.send(AdbPacket.wrte, 6, 106, [6]);
    expect((await remote.packet()).data, [6]);
    await remote.send(AdbPacket.wrte, 106, 6, [7]);
    expect((await local.packet()).data, [7]);
    await local.send(AdbPacket.okay, 6, 106);
    expect((await remote.packet()).command, AdbPacket.okay);
  });

  test('源端发起的 Reverse 不接管 ACK，也不改写任何服务字节', () async {
    await negotiate();
    final name = utf8.encode('tcp:8081\u0000');
    await remote.send(AdbPacket.open, 91, 0, name);
    expect((await local.packet()).data, name);
    await local.send(AdbPacket.okay, 92, 91);
    expect((await remote.packet()).arg0, 92);
    await local.send(AdbPacket.wrte, 92, 91, [1, 2]);
    expect((await remote.packet()).data, [1, 2]);
    await remote.send(AdbPacket.okay, 91, 92);
    expect((await local.packet()).command, AdbPacket.okay);
  });

  test('4096 字节旧 Transport 达到上限时必须等待远端 ACK', () async {
    await negotiate(4096);
    await open('sync:', 1);
    await write(1, 7);
    expect((await remote.packet()).data.length, 4096);
    await remote.send(AdbPacket.wrte, 900, 901, [88]);
    expect((await local.packet()).command, AdbPacket.wrte);
    await remote.send(AdbPacket.okay, 101, 1);
    await expectAck(1);
  });

  test('本地 ACK 仍排在出口队列时不能接纳第二块未确认 WRTE', () async {
    await open('sync:', 1);
    localWriter.gate = Completer<void>();
    await remote.send(AdbPacket.wrte, 900, 901, [88]);
    expect((await local.packet()).data, [88]);
    await localWriter.entered.future;
    await write(1, 1);
    expect((await remote.packet()).data, List.filled(4096, 1));
    await write(1, 2);
    final closed = await remote.packet();
    expect((closed.command, closed.arg0), (AdbPacket.clse, 1));
    localWriter.gate!.complete();
    expect((await local.packet()).command, AdbPacket.clse);
  });

  test('零字节 WRTE 不积压远端队列，也不生成空聚合包', () async {
    await open('sync:', 1);
    for (var i = 0; i < 10; i++) {
      await write(1, 1, 0);
      await expectAck(1);
    }
    await write(1, 9);
    expect((await remote.packet()).data, List.filled(4096, 9));
    await expectAck(1);
  });

  test('远端输入关闭仅记录方向和异常类型，不包含原始数据', () async {
    await negotiate();
    remote.peer.destroy();
    await running;
    expect(diagnostics, [
      'relay_input_closed direction=remote error_type=SocketException',
    ]);
  });
}
