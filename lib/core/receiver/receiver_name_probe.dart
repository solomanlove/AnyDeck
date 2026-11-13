import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Bonjour 命令输出、SSDP 搜索和描述读取均可替换，测试无需真实局域网。
typedef ReceiverBonjourRunner = Future<List<String>> Function(Duration timeout);
typedef ReceiverSsdpSearch =
    Future<List<ReceiverSsdpReply>> Function(Duration timeout);
typedef ReceiverDescriptionReader =
    Future<String?> Function(Uri location, Duration timeout);

/// 一次 SSDP 应答；保留发送方地址，限制后续 HTTP 请求到该发送方。
class ReceiverSsdpReply {
  const ReceiverSsdpReply({required this.message, required this.sender});

  final String message;
  final InternetAddress sender;
}

/// 启动前进行有界、尽力而为的重名探测；异常不阻止接收服务启动。
///
/// AirPlay 仅在 macOS 调用系统 dns-sd。DLNA 只读取应答设备的描述，
/// 不订阅服务、不调用播放器。调用方应避免探测正在运行的本机服务。
/// 这不是名称锁：同时启动的电脑仍可能在探测结束后出现重名。
class ReceiverNameProbe {
  ReceiverNameProbe({
    ReceiverBonjourRunner? bonjourRunner,
    ReceiverSsdpSearch? ssdpSearch,
    ReceiverDescriptionReader? descriptionReader,
    bool? isMacOS,
    this.timeout = const Duration(seconds: 2),
  }) : _bonjourRunner = bonjourRunner ?? _browseBonjour,
       _ssdpSearch = ssdpSearch ?? _searchSsdp,
       _descriptionReader = descriptionReader ?? _readDescription,
       _isMacOS = isMacOS ?? Platform.isMacOS;

  static const _rendererType = 'urn:schemas-upnp-org:device:MediaRenderer:1';
  static const _maxReplies = 32;
  static const _maxDescriptions = 8;
  static const _maxDescriptionBytes = 64 * 1024;
  final ReceiverBonjourRunner _bonjourRunner;
  final ReceiverSsdpSearch _ssdpSearch;
  final ReceiverDescriptionReader _descriptionReader;
  final bool _isMacOS;
  final Duration timeout;

  Future<bool> hasConflict({
    required String name,
    required String protocol,
    required String localUuid,
  }) async {
    if (name.trim().isEmpty || timeout <= Duration.zero) return false;
    try {
      if (protocol == 'AirPlay' && _isMacOS) {
        final lines = await _bonjourRunner(
          timeout,
        ).timeout(timeout + const Duration(milliseconds: 600));
        return lines.take(512).any((line) => bonjourName(line) == name);
      }
      if (protocol != 'DLNA') return false;
      final watch = Stopwatch()..start();
      // 默认接收窗口超过 SSDP MX: 1，给完整应答窗口和描述读取都留出预算。
      final searchBudget = Duration(
        microseconds: timeout.inMicroseconds * 2 ~/ 3,
      );
      final replies = await _ssdpSearch(
        searchBudget,
      ).timeout(searchBudget + const Duration(milliseconds: 50));
      final locations = <Uri>{};
      for (final reply in replies.take(_maxReplies)) {
        final location = ssdpLocation(reply, localUuid: localUuid);
        if (location != null) locations.add(location);
        if (locations.length >= _maxDescriptions) break;
      }
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero || locations.isEmpty) return false;
      final names = await Future.wait(
        locations.map((location) async {
          try {
            final xml = await _descriptionReader(
              location,
              remaining,
            ).timeout(remaining);
            if (xml == null || xml.length > _maxDescriptionBytes) return null;
            return friendlyName(xml);
          } catch (_) {
            return null;
          }
        }),
      );
      return names.contains(name);
    } catch (_) {
      return false;
    }
  }

  /// 仅接受 dns-sd 的 Add 记录，保留名称内的空格与中文，禁止子串匹配。
  static String? bonjourName(String line) => RegExp(
    r'^\S+\s+Add\s+\S+\s+\d+\s+local\.\s+_airplay\._tcp\.?\s+(.+)$',
  ).firstMatch(line)?.group(1)?.trim();

  /// 只允许访问应答者自身的 IPv4 HTTP 地址，不解析域名或跟随跳转。
  static Uri? ssdpLocation(
    ReceiverSsdpReply reply, {
    required String localUuid,
  }) {
    if (reply.message.length > 8192 ||
        !reply.message.startsWith('HTTP/1.1 200')) {
      return null;
    }
    final headers = <String, String>{};
    for (final line in const LineSplitter().convert(reply.message).skip(1)) {
      final separator = line.indexOf(':');
      if (separator > 0) {
        headers[line.substring(0, separator).trim().toUpperCase()] = line
            .substring(separator + 1)
            .trim();
      }
    }
    if (headers['ST'] != _rendererType) return null;
    final usn = headers['USN']?.toLowerCase() ?? '';
    final uuid = usn.split('::').first;
    final ownUuid = localUuid.toLowerCase().replaceFirst(RegExp(r'^uuid:'), '');
    if (!uuid.startsWith('uuid:') ||
        uuid.length <= 5 ||
        (ownUuid.isNotEmpty && uuid == 'uuid:$ownUuid')) {
      return null;
    }
    final uri = Uri.tryParse(headers['LOCATION'] ?? '');
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.port <= 0 ||
        uri.port > 65535 ||
        uri.host != reply.sender.address ||
        !_isLocalIpv4(reply.sender)) {
      return null;
    }
    return uri;
  }

  /// XML parser 负责标准实体解码；拒绝 DTD，避免外部实体和实体扩展。
  static String? friendlyName(String xml) {
    if (xml.length > _maxDescriptionBytes ||
        xml.toUpperCase().contains('<!DOCTYPE')) {
      return null;
    }
    try {
      final document = XmlDocument.parse(xml);
      for (final device in document.descendants.whereType<XmlElement>()) {
        if (device.name.local != 'device') continue;
        String? field(String name) {
          for (final child in device.childElements) {
            if (child.name.local == name) return child.innerText.trim();
          }
          return null;
        }

        if (field('deviceType') == _rendererType) return field('friendlyName');
      }
    } catch (_) {
      // 不完整或非 XML 的设备应答不影响其他接收端的探测。
    }
    return null;
  }

  static bool _isLocalIpv4(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        bytes[0] == 127 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168) ||
        (bytes[0] == 169 && bytes[1] == 254);
  }

  static Future<List<String>> _browseBonjour(Duration timeout) async {
    final watch = Stopwatch()..start();
    Process? process;
    StreamSubscription<List<int>>? output;
    StreamSubscription<List<int>>? errors;
    Timer? timer;
    final bytes = BytesBuilder(copy: false);
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    try {
      final starting = Process.start('/usr/bin/dns-sd', [
        '-B',
        '_airplay._tcp',
        'local.',
      ]);
      process = await starting.timeout(
        timeout,
        onTimeout: () {
          // Process.start 超时后若系统最终返回进程，仍要将其终止并回收。
          unawaited(
            starting
                .then((lateProcess) async {
                  lateProcess.kill(ProcessSignal.sigkill);
                  await lateProcess.stdout.drain<void>();
                  await lateProcess.stderr.drain<void>();
                  await lateProcess.exitCode;
                })
                .catchError((_) {}),
          );
          throw TimeoutException('Bonjour start timed out');
        },
      );
      output = process.stdout.listen(
        (chunk) {
          final available = _maxDescriptionBytes - bytes.length;
          if (available <= 0) return finish();
          bytes.add(
            chunk.length <= available ? chunk : chunk.sublist(0, available),
          );
          if (bytes.length >= _maxDescriptionBytes) finish();
        },
        onError: (_) => finish(),
        onDone: finish,
      );
      errors = process.stderr.listen((_) {}, onError: (_) {});
      unawaited(process.exitCode.then((_) => finish()));
      timer = Timer(timeout - watch.elapsed, finish);
      await done.future;
    } finally {
      timer?.cancel();
      try {
        if (process != null) {
          process.kill();
          try {
            await process.exitCode.timeout(const Duration(milliseconds: 200));
          } on TimeoutException {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode.timeout(const Duration(milliseconds: 200));
          }
        }
      } finally {
        await output?.cancel();
        await errors?.cancel();
      }
    }
    return const LineSplitter().convert(
      utf8.decode(bytes.takeBytes(), allowMalformed: true),
    );
  }

  static Future<List<ReceiverSsdpReply>> _searchSsdp(Duration timeout) async {
    final watch = Stopwatch()..start();
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? timer;
    final done = Completer<void>();
    final replies = <ReceiverSsdpReply>[];
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    try {
      final binding = RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket = await binding.timeout(
        timeout,
        onTimeout: () {
          unawaited(binding.then((lateSocket) => lateSocket.close()));
          throw TimeoutException('SSDP bind timed out');
        },
      );
      subscription = socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          final packet = socket?.receive();
          if (packet == null || packet.data.length > 8192) return;
          replies.add(
            ReceiverSsdpReply(
              message: utf8.decode(packet.data, allowMalformed: true),
              sender: packet.address,
            ),
          );
          if (replies.length >= _maxReplies) finish();
        },
        onError: (_) => finish(),
        onDone: finish,
      );
      const request =
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\nMX: 1\r\n'
          'ST: $_rendererType\r\n\r\n';
      socket.send(
        ascii.encode(request),
        InternetAddress('239.255.255.250'),
        1900,
      );
      timer = Timer(timeout - watch.elapsed, finish);
      await done.future;
    } finally {
      timer?.cancel();
      socket?.close();
      await subscription?.cancel();
    }
    return replies;
  }

  static Future<String?> _readDescription(
    Uri location,
    Duration timeout,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = false;
    try {
      return await (() async {
        final request = await client.getUrl(location);
        request.followRedirects = false;
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok ||
            response.contentLength > _maxDescriptionBytes) {
          return null;
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > _maxDescriptionBytes) return null;
          bytes.add(chunk);
        }
        return utf8.decode(bytes.takeBytes(), allowMalformed: true);
      })().timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
