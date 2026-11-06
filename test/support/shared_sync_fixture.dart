import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/core/device_share/share_socket_reader.dart';

/// 最小 ADB Sync v1 对端，验证真实 adb push/pull 经过共享通道后的文件内容。
class SharedSyncFixture {
  final files = <String, Uint8List>{};

  Uint8List _header(String id, int size) {
    final bytes = Uint8List(8)..setRange(0, 4, ascii.encode(id));
    ByteData.sublistView(bytes).setUint32(4, size, Endian.little);
    return bytes;
  }

  Future<void> handle(Socket socket, ShareSocketReader reader) async {
    while (true) {
      final header = await reader.read(8);
      final command = ascii.decode(header.sublist(0, 4));
      final length = ByteData.sublistView(header).getUint32(4, Endian.little);
      if (command == 'QUIT') return;
      if (length > 65536) {
        throw const FormatException('Sync test request too large');
      }
      final path = utf8.decode(await reader.read(length));
      switch (command) {
        case 'STAT':
          final stat = Uint8List(16)..setRange(0, 4, ascii.encode('STAT'));
          final values = ByteData.sublistView(stat);
          values.setUint32(
            4,
            files.containsKey(path) ? 0x81a4 : 0,
            Endian.little,
          );
          values.setUint32(8, files[path]?.length ?? 0, Endian.little);
          socket.add(stat);
        case 'SEND':
          final bytes = BytesBuilder();
          while (true) {
            final part = await reader.read(8);
            if (ascii.decode(part.sublist(0, 4)) == 'DONE') break;
            final size = ByteData.sublistView(part).getUint32(4, Endian.little);
            bytes.add(await reader.read(size));
          }
          files[path.substring(0, path.lastIndexOf(','))] = bytes.takeBytes();
          socket.add(_header('OKAY', 0));
        case 'RECV':
          final file = files[path]!;
          for (var offset = 0; offset < file.length; offset += 65536) {
            final end = (offset + 65536).clamp(0, file.length);
            socket.add(_header('DATA', end - offset));
            socket.add(file.sublist(offset, end));
          }
          socket.add(_header('DONE', 0));
        default:
          throw FormatException('Unsupported Sync test command: $command');
      }
      await socket.flush();
    }
  }
}
