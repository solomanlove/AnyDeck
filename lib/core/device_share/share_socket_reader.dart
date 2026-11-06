import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 顺序读取 Socket，保留握手后的剩余字节；StreamIterator 使慢消费者产生背压。
class ShareSocketReader {
  ShareSocketReader(Stream<Uint8List> stream)
    : _iterator = StreamIterator(stream);

  final StreamIterator<Uint8List> _iterator;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;

  Future<Uint8List?> readChunk([int limit = 1024 * 1024]) async {
    while (_offset == _chunk.length) {
      if (!await _iterator.moveNext()) return null;
      _chunk = _iterator.current;
      _offset = 0;
    }
    final end = (_offset + limit).clamp(0, _chunk.length);
    final value = Uint8List.sublistView(_chunk, _offset, end);
    _offset = end;
    return value;
  }

  Future<Uint8List> read(int length) async {
    final result = Uint8List(length);
    var offset = 0;
    while (offset < length) {
      final chunk = await readChunk(length - offset);
      if (chunk == null) {
        throw const SocketException('Shared connection closed');
      }
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  /// 控制消息独立限长，拒绝在认证前分配任意大小的内存。
  Future<Map<String, dynamic>> readMessage() async {
    final header = await read(4);
    final size = ByteData.sublistView(header).getUint32(0);
    if (size > 4096) throw const FormatException('Share message too large');
    return jsonDecode(utf8.decode(await read(size))) as Map<String, dynamic>;
  }

  Future<void> cancel() => _iterator.cancel();
}

/// 控制消息只在 TLS 建立后发送，分享令牌不写入日志或磁盘。
Future<void> writeShareMessage(
  Socket socket,
  Map<String, Object?> value,
) async {
  final bytes = utf8.encode(jsonEncode(value));
  final header = ByteData(4)..setUint32(0, bytes.length);
  socket.add(header.buffer.asUint8List());
  socket.add(bytes);
  await socket.flush();
}
