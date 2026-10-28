import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'share_core_contract.dart';
import 'share_core_sessions.dart';

export 'share_core_contract.dart';
export 'share_core_sessions.dart';

/// 私有 Share Core 的公开 IPC 契约；不包含任何 Huawei Share 协议字段。
class ShareCoreCapabilities {
  const ShareCoreCapabilities({
    required this.discovery,
    required this.send,
    required this.receive,
    required this.coreVersion,
    required this.maxFileBytes,
  });

  final bool discovery;
  final bool send;
  final bool receive;
  final String coreVersion;
  final int maxFileBytes;

  /// 仅接受与当前主仓库兼容的握手版本与明确声明的布尔能力。
  static ShareCoreCapabilities parse(String line) {
    final value = jsonDecode(line);
    if (value is! Map<String, dynamic> ||
        value['event'] != 'hello' ||
        value['version'] != ShareCoreContract.version ||
        value['core_version'] is! String) {
      throw const FormatException('Incompatible Share Core handshake');
    }
    final capabilities = value['capabilities'];
    if (capabilities is! Map<String, dynamic> ||
        capabilities['discovery'] is! bool ||
        capabilities['send'] is! bool ||
        capabilities['receive'] is! bool) {
      throw const FormatException('Invalid Share Core capabilities');
    }
    final experimental = value['experimental'];
    if (experimental is! Map<String, dynamic> ||
        experimental['max_file_bytes'] != ShareCoreContract.maxFileBytes ||
        experimental['max_transfer_seconds'] !=
            ShareCoreContract.transferTimeout.inSeconds ||
        experimental['progress'] != true ||
        experimental['graceful_cancel'] != true) {
      throw const FormatException(
        'Incompatible experimental transfer contract',
      );
    }
    return ShareCoreCapabilities(
      discovery: capabilities['discovery'] as bool,
      send: capabilities['send'] as bool,
      receive: capabilities['receive'] as bool,
      coreVersion: value['core_version'] as String,
      maxFileBytes: experimental['max_file_bytes'] as int,
    );
  }
}

/// 私有核心发现的局域网设备摘要；只暴露界面需要的字段。
class ShareCorePeer {
  const ShareCorePeer({
    required this.address,
    required this.port,
    required this.name,
  });

  final InternetAddress address;
  final int port;
  final String name;

  /// 拒绝格式错误或超出端口范围的核心进程输出。
  static ShareCorePeer parse(Map<String, dynamic> value) {
    final address = InternetAddress.tryParse(value['ip']?.toString() ?? '');
    final port = value['port'];
    final name = value['name'];
    if (value['event'] != 'device' ||
        address == null ||
        address.type != InternetAddressType.IPv4 ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        name is! String ||
        name.length > 256) {
      throw const FormatException('Invalid Share Core peer');
    }
    return ShareCorePeer(address: address, port: port, name: name);
  }
}

/// 启动 App 包内已校验的原生服务；握手失败时显式报错，绝不降级执行外部脚本。
class ShareCoreClient {
  const ShareCoreClient();

  File get _executable {
    final macOS = Platform.resolvedExecutable;
    return File('${File(macOS).parent.path}/ShareCore/anydeck-share-core');
  }

  Future<ShareCoreCapabilities> probe() async {
    if (!Platform.isMacOS || !await _executable.exists()) {
      throw const FileSystemException('Share Core is not bundled');
    }
    final process = await Process.start(_executable.path, const []);
    try {
      process.stdin.writeln(
        jsonEncode({'version': ShareCoreContract.version, 'command': 'hello'}),
      );
      await process.stdin.flush();
      final line = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5));
      return ShareCoreCapabilities.parse(line);
    } finally {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
  }

  /// 按指定网卡地址发现设备；关闭订阅会终止独立原生进程。
  Stream<ShareCorePeer> discover({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Duration duration,
  }) async* {
    if (!Platform.isMacOS || !await _executable.exists()) {
      throw const FileSystemException('Share Core is not bundled');
    }
    if (localAddress.type != InternetAddressType.IPv4 ||
        broadcastAddress.type != InternetAddressType.IPv4 ||
        duration.inSeconds < 1 ||
        duration.inSeconds > 120) {
      throw const FormatException('Invalid Share Core discovery request');
    }
    final process = await Process.start(_executable.path, const []);
    try {
      process.stdin.writeln(
        jsonEncode({
          'version': ShareCoreContract.version,
          'command': 'discover',
          'local_ip': localAddress.address,
          'broadcast_ip': broadcastAddress.address,
          'duration_seconds': duration.inSeconds,
        }),
      );
      await process.stdin.flush();
      await for (final line
          in process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(duration + const Duration(seconds: 5))) {
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid Share Core response');
        }
        switch (value['event']) {
          case 'device':
            yield ShareCorePeer.parse(value);
            break;
          case 'discovery_finished':
            return;
          case 'error':
            throw StateError('Share Core discovery failed: ${value['code']}');
          default:
            throw const FormatException('Unexpected Share Core response');
        }
      }
      throw const FormatException('Share Core closed discovery unexpectedly');
    } finally {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
  }

  /// 测试入口仅传输一个不超过 1 GiB 的普通文件；私有核心仍要求显式环境开关。
  Future<ShareCoreTransfer> sendFileForTest({
    required InternetAddress localAddress,
    required ShareCorePeer peer,
    required File file,
  }) async {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size < 1 ||
        stat.size > ShareCoreContract.maxFileBytes) {
      throw const FormatException('Select one nonempty file up to 1 GiB');
    }
    return _startTransfer({
      'command': 'send_file_experimental',
      'peer_ip': peer.address.address,
      'port': peer.port,
      'local_ip': localAddress.address,
      'path': file.path,
    }, expectedEvent: 'file_sent');
  }

  /// 目录必须尚不存在，由私有核心以受限权限创建，避免覆盖用户文件。
  Future<ShareCoreTransfer> receiveFileForTest({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required InternetAddress peerAddress,
    required Directory outputDirectory,
  }) async {
    if (await outputDirectory.exists() ||
        !await outputDirectory.parent.exists()) {
      throw const FormatException('Receive folder must be new');
    }
    return _startTransfer({
      'command': 'receive_file_experimental',
      'peer_ip': peerAddress.address,
      'local_ip': localAddress.address,
      'broadcast_ip': broadcastAddress.address,
      'output_dir': outputDirectory.path,
    }, expectedEvent: 'file_received');
  }

  /// 启动不绑定特定手机的接收窗口；所有认证与传输逻辑由私有核心完成。
  Future<ShareCoreReceiveSession> startInteractiveReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
  }) async {
    if (!Platform.isMacOS || !await _executable.exists()) {
      throw const FileSystemException('Share Core is not bundled');
    }
    if (await outputDirectory.exists() ||
        !await outputDirectory.parent.exists()) {
      throw const FormatException('Receive folder must be new');
    }
    await probe();
    final process = await Process.start(
      _executable.path,
      const [],
      environment: const {'ANYDECK_SHARE_EXPERIMENTAL': '1'},
    );
    final session = ShareCoreReceiveSession(process);
    process.stdin.writeln(
      jsonEncode({
        'version': ShareCoreContract.version,
        'command': 'receive_file_interactive',
        'local_ip': localAddress.address,
        'broadcast_ip': broadcastAddress.address,
        'output_dir': outputDirectory.path,
        'duration_seconds': 120,
      }),
    );
    await process.stdin.flush();
    return session;
  }

  Future<ShareCoreTransfer> _startTransfer(
    Map<String, Object> request, {
    required String expectedEvent,
  }) async {
    if (!Platform.isMacOS || !await _executable.exists()) {
      throw const FileSystemException('Share Core is not bundled');
    }
    await probe();
    final process = await Process.start(
      _executable.path,
      const [],
      environment: const {'ANYDECK_SHARE_EXPERIMENTAL': '1'},
    );
    try {
      final transfer = ShareCoreTransfer(process, expectedEvent);
      process.stdin.writeln(
        jsonEncode({
          'version': ShareCoreContract.version,
          ...request,
          'duration_seconds': expectedEvent == 'file_sent'
              ? ShareCoreContract.transferTimeout.inSeconds
              : 120,
        }),
      );
      await process.stdin.flush();
      await process.stdin.close();
      return transfer;
    } catch (_) {
      process.kill();
      rethrow;
    }
  }
}
