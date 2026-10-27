import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 私有 Share Core 的公开 IPC 契约；不包含任何 Huawei Share 协议字段。
class ShareCoreCapabilities {
  const ShareCoreCapabilities({
    required this.discovery,
    required this.send,
    required this.receive,
    required this.coreVersion,
  });

  final bool discovery;
  final bool send;
  final bool receive;
  final String coreVersion;

  /// 仅接受与当前主仓库兼容的握手版本与明确声明的布尔能力。
  static ShareCoreCapabilities parse(String line) {
    final value = jsonDecode(line);
    if (value is! Map<String, dynamic> ||
        value['event'] != 'hello' ||
        value['version'] != 1 ||
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
    return ShareCoreCapabilities(
      discovery: capabilities['discovery'] as bool,
      send: capabilities['send'] as bool,
      receive: capabilities['receive'] as bool,
      coreVersion: value['core_version'] as String,
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
      process.stdin.writeln(jsonEncode({'version': 1, 'command': 'hello'}));
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
          'version': 1,
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
}
