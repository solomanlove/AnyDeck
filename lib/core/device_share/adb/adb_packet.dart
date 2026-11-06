import 'dart:typed_data';

import '../share_socket_reader.dart';

/// ADB Transport 报文；长度与 magic 校验在读取 payload 前完成。
class AdbPacket {
  AdbPacket(this.command, this.arg0, this.arg1, [Uint8List? data])
    : data = data ?? Uint8List(0);

  static const cnxn = 0x4e584e43,
      open = 0x4e45504f,
      okay = 0x59414b4f,
      wrte = 0x45545257,
      clse = 0x45534c43;
  static const maxPayload = 1024 * 1024;
  final int command, arg0, arg1;
  final Uint8List data;

  static Future<AdbPacket> read(ShareSocketReader reader) async {
    final header = ByteData.sublistView(await reader.read(24));
    final command = header.getUint32(0, Endian.little);
    final size = header.getUint32(12, Endian.little);
    if (size > maxPayload ||
        header.getUint32(20, Endian.little) != (command ^ 0xffffffff)) {
      throw const FormatException('Invalid ADB packet');
    }
    final data = await reader.read(size);
    final checksum = header.getUint32(16, Endian.little);
    if (checksum != 0 && checksum != data.fold<int>(0, (a, b) => a + b)) {
      throw const FormatException('Invalid ADB checksum');
    }
    return AdbPacket(
      command,
      header.getUint32(4, Endian.little),
      header.getUint32(8, Endian.little),
      data,
    );
  }

  Uint8List encode() {
    final bytes = Uint8List(24 + data.length);
    final header = ByteData.sublistView(bytes);
    header.setUint32(0, command, Endian.little);
    header.setUint32(4, arg0, Endian.little);
    header.setUint32(8, arg1, Endian.little);
    header.setUint32(12, data.length, Endian.little);
    header.setUint32(16, data.fold<int>(0, (a, b) => a + b), Endian.little);
    header.setUint32(20, command ^ 0xffffffff, Endian.little);
    bytes.setRange(24, bytes.length, data);
    return bytes;
  }
}
