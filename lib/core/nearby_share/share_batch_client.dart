import 'dart:convert';
import 'dart:io';

import 'share_batch_contract.dart';
import 'share_batch_sessions.dart';
import 'share_core_sessions.dart';

/// 通用批次 IPC 调用边界；probe/launch 可注入离线进程测试，失败时回收已启动进程。
class ShareBatchClient {
  const ShareBatchClient({required this.probe, required this.launch});
  final Future<void> Function() probe;
  final Future<Process> Function() launch;

  Future<ShareBatchTransfer> send({
    required ShareBatchRequest request,
    required InternetAddress local,
    required InternetAddress peer,
    required int port,
  }) async {
    final value = request.request(
      localIp: local.address,
      peerIp: peer.address,
      port: port,
    );
    await probe();
    final process = await launch();
    try {
      final session = ShareBatchTransfer(process, request);
      process.stdin.writeln(jsonEncode(value));
      await process.stdin.flush();
      await process.stdin.close();
      return session;
    } catch (_) {
      await stopShareCoreProcess(process);
      rethrow;
    }
  }

  Future<ShareBatchReceiveSession> receive({
    required InternetAddress local,
    required InternetAddress broadcast,
    required Directory output,
  }) async {
    if (local.type != InternetAddressType.IPv4 ||
        broadcast.type != InternetAddressType.IPv4 ||
        !output.isAbsolute ||
        await FileSystemEntity.type(output.path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        !await output.parent.exists()) {
      throw const FormatException(
        'Invalid batch receive destination or address',
      );
    }
    final value = {
      'version': ShareBatchContract.version,
      'command': 'receive_batch_interactive',
      'local_ip': local.address,
      'broadcast_ip': broadcast.address,
      'output_dir': output.path,
      'duration_seconds': 120,
    };
    if (utf8.encode(jsonEncode(value)).length > 65536) {
      throw const FormatException('Batch request too large');
    }
    await probe();
    final process = await launch();
    final session = ShareBatchReceiveSession(process, directory: output.path);
    try {
      process.stdin.writeln(jsonEncode(value));
      await process.stdin.flush();
      return session;
    } catch (_) {
      await session.stop();
      rethrow;
    }
  }
}
