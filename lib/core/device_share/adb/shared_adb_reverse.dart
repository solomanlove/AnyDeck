import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'shared_adb_backend.dart';

/// Reverse 规则只属于当前共享会话，不覆盖或删除宿主其他工具的规则。
class SharedAdbReverse {
  SharedAdbReverse(this.backend, this.onConnection);
  final SharedAdbBackend backend;
  final void Function(String destination, Socket socket) onConnection;
  final _rules = <String, ({ServerSocket server, String destination})>{};
  final _pending = <Future<Uint8List>>{};
  Future<void>? _closing;
  bool _closed = false;

  Uint8List _reply(String value) => Uint8List.fromList(ascii.encode(value));
  Uint8List _failure() {
    const reason = 'Reverse rule unavailable';
    return _reply(
      'FAIL${reason.length.toRadixString(16).padLeft(4, '0')}$reason',
    );
  }

  Future<Uint8List> handle(String service) {
    final operation = _handle(service);
    _pending.add(operation);
    return operation.whenComplete(() => _pending.remove(operation));
  }

  Future<Uint8List> _handle(String service) async {
    if (_closed) return _failure();
    if (service == 'reverse:list-forward') {
      final data = _rules.entries
          .map((entry) => 'AnyDeck ${entry.key} ${entry.value.destination}\n')
          .join();
      return _reply('${data.length.toRadixString(16).padLeft(4, '0')}$data');
    }
    if (service == 'reverse:killforward-all') {
      await Future.wait(_rules.keys.toList().map(_remove));
      return _reply('OKAY');
    }
    if (service.startsWith('reverse:killforward:')) {
      final remote = service.substring('reverse:killforward:'.length);
      if (!_rules.containsKey(remote)) return _failure();
      return _remove(remote);
    }
    final match = RegExp(
      r'^reverse:forward:(norebind:)?tcp:(\d+);tcp:(\d+)$',
    ).firstMatch(service);
    if (match == null) return _failure();
    final remotePort = int.parse(match[2]!);
    final localPort = int.parse(match[3]!);
    if (remotePort > 65535 || localPort < 1 || localPort > 65535) {
      return _failure();
    }
    final remote = 'tcp:$remotePort';
    if (!_rules.containsKey(remote) && _rules.length + _pending.length >= 16) {
      return _failure();
    }
    if (_rules.containsKey(remote)) {
      if (match[1] != null) return _failure();
      await _remove(remote);
    }
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final response = await backend.reverse(
        'reverse:forward:norebind:$remote;tcp:${server.port}',
      );
      if (response.length < 4 ||
          ascii.decode(response.sublist(0, 4)) != 'OKAY') {
        await server.close();
        return _closed ? _failure() : response;
      }
      var assignedRemote = remote;
      if (remotePort == 0) {
        if (response.length < 9) {
          throw const FormatException('Missing reverse port');
        }
        final port = int.parse(ascii.decode(response.sublist(8)));
        if (port < 1 || port > 65535) {
          throw const FormatException('Invalid reverse port');
        }
        assignedRemote = 'tcp:$port';
      }
      if (_closed) {
        await server.close();
        await backend.reverse('reverse:killforward:$assignedRemote');
        return _failure();
      }
      _rules[assignedRemote] = (server: server, destination: 'tcp:$localPort');
      server.listen((socket) {
        if (_closed) {
          socket.destroy();
          return;
        }
        onConnection('tcp:$localPort', socket);
      }, onError: (_) {});
      return response;
    } catch (_) {
      await server.close();
      return _failure();
    }
  }

  Future<Uint8List> _remove(String remote) async {
    final rule = _rules.remove(remote);
    await rule?.server.close();
    try {
      return await backend.reverse('reverse:killforward:$remote');
    } catch (_) {
      return _failure();
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    // 等待已发往 adbd 的创建请求结束并撤销，避免停止时留下迟到的 Reverse 规则。
    await Future.wait(
      _pending.toList().map(
        (operation) => operation.catchError((_) => Uint8List(0)),
      ),
    );
    await Future.wait(_rules.keys.toList().map(_remove));
  }
}
