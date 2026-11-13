import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../receiver/receiver_name_probe.dart';
import '../receiver/receiver_names.dart';

/// 复用接收端 SSDP 数据，在运行中发现同名电脑并请求稳定改名。
///
/// [baseName] 是用户请求的原始名称，自动增加短码后仍保持原值。
/// [currentName] 读取实际广播名称；[onConflict] 接收原始名称与候选名称，
/// 调用方应在异步持久化和改名前再次核对 expectedBaseName，避免覆盖用户改名。
/// [descriptionReader] 可注入无网络替身；默认读取器由本类持有并主动释放。
class DlnaNameConflictMonitor {
  DlnaNameConflictMonitor({
    required this.uuid,
    required String baseName,
    required String Function() currentName,
    required Future<void> Function(String expectedBaseName, String fallbackName)
    onConflict,
    ReceiverDescriptionReader? descriptionReader,
    this.requestTimeout = const Duration(seconds: 1),
    this.cacheTtl = const Duration(seconds: 30),
  }) : _baseName = baseName.trim(),
       _currentName = currentName,
       _onConflict = onConflict,
       _descriptionReader = descriptionReader;

  static const _maxDevices = 32;
  static const _maxConcurrent = 2;
  static const _maxBytes = 64 * 1024;
  static const _lengths = [6, 12, 32];
  final String uuid;
  final String Function() _currentName;
  final Future<void> Function(String, String) _onConflict;
  final ReceiverDescriptionReader? _descriptionReader;
  final Duration requestTimeout;
  final Duration cacheTtl;
  final _seen = <String, DateTime>{};
  final _queue = <_NameObservation>[];
  final _clients = <HttpClient>{};
  String _baseName;
  int _generation = 0;
  int _running = 0;
  bool _disposed = false;
  Completer<void>? _idle;
  Future<void> _renames = Future<void>.value();

  /// 测试可等待已排入的任务结束；产品逻辑无需等待局域网描述请求。
  Future<void> get idle => _idle?.future ?? Future<void>.value();

  /// NOTIFY 和 M-SEARCH 应答共用校验、去重、缓存与并发限制。
  void observe(ReceiverSsdpReply packet) {
    if (_disposed || _baseName.isEmpty || requestTimeout <= Duration.zero) {
      return;
    }
    try {
      final normalized = _normalize(packet);
      if (normalized == null) return;
      final location = ReceiverNameProbe.ssdpLocation(
        normalized,
        localUuid: uuid,
      );
      if (location == null) return;
      final remoteUuid = _headers(normalized.message)['USN']!
          .split('::')
          .first
          .replaceFirst(RegExp(r'^uuid:', caseSensitive: false), '');
      final publishedName = _currentName();
      // 自动改名后允许立即重查同一对端，不必等待旧缓存过期。
      final key = '${remoteUuid.toLowerCase()}|$location|$publishedName';
      final now = DateTime.now();
      _seen.removeWhere((_, expires) => !expires.isAfter(now));
      if (_seen.containsKey(key) || _running + _queue.length >= _maxDevices) {
        return;
      }
      if (_seen.length >= _maxDevices) _seen.remove(_seen.keys.first);
      _seen[key] = now.add(cacheTtl);
      _idle ??= Completer<void>();
      _queue.add(
        _NameObservation(
          location,
          remoteUuid,
          _baseName,
          publishedName,
          _generation,
        ),
      );
      _pump();
    } catch (_) {
      // 畸形报文或无法解析的端口只影响本次观察，不影响接收端运行。
    }
  }

  /// 用户改变原始名称时使旧查询失效；自动短码改名不要改变 baseName。
  void updateName(String baseName) {
    if (_disposed || _baseName == baseName.trim()) return;
    _baseName = baseName.trim();
    _invalidate();
  }

  /// 停止服务后禁止迟到结果改名，并关闭仍在读取的 HTTP 连接。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _invalidate();
  }

  void _invalidate() {
    _generation++;
    _queue.clear();
    _seen.clear();
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _finishIdle();
  }

  void _pump() {
    while (!_disposed && _running < _maxConcurrent && _queue.isNotEmpty) {
      final observation = _queue.removeAt(0);
      _running++;
      unawaited(
        _inspect(observation).whenComplete(() {
          _running--;
          _pump();
          _finishIdle();
        }),
      );
    }
  }

  void _finishIdle() {
    if (_running != 0 || _queue.isNotEmpty) return;
    _idle?.complete();
    _idle = null;
  }

  bool _isCurrent(_NameObservation observation) =>
      !_disposed &&
      observation.generation == _generation &&
      observation.baseName == _baseName;

  Future<void> _inspect(_NameObservation observation) async {
    try {
      if (!_isCurrent(observation)) return;
      final xml = await (_descriptionReader ?? _readDescription)(
        observation.location,
        requestTimeout,
      ).timeout(requestTimeout);
      if (!_isCurrent(observation) || xml == null || xml.length > _maxBytes) {
        return;
      }
      final remoteName = ReceiverNameProbe.friendlyName(xml);
      if (remoteName == null ||
          !_matchesPeer(
            observation.baseName,
            remoteName,
            observation.remoteUuid,
          )) {
        return;
      }
      // 两个描述可并行读取，名称回调串行执行，避免重复写入与降级。
      final previous = _renames;
      _renames = () async {
        await previous;
        if (!_isCurrent(observation)) return;
        final published = _currentName();
        final ownCode = _compactUuid(uuid);
        if (ownCode == null) return;
        final existingLength = _codeLength(
          observation.baseName,
          published,
          ownCode,
        );
        if (published != observation.publishedName && existingLength == 0) {
          return;
        }
        if (existingLength == 0 && published != observation.baseName) return;
        final remoteCode = _compactUuid(observation.remoteUuid);
        var length = 6;
        if (remoteCode != null) {
          length = _lengths.firstWhere(
            (size) =>
                ownCode.substring(0, size) != remoteCode.substring(0, size),
            orElse: () => 32,
          );
        }
        if (existingLength > length) length = existingLength;
        final fallback = ReceiverNames.stableFallback(
          observation.baseName,
          'DLNA',
          ownCode,
          codeLength: length,
        );
        if (fallback == published) return;
        await _onConflict(observation.baseName, fallback);
      }().catchError((_) {});
      await _renames;
    } catch (_) {
      // 局域网权限、离线、超时和改名失败均不应打断正在播放的内容。
    }
  }

  static String? _compactUuid(String value) {
    final compact = value
        .replaceFirst(RegExp(r'^uuid:', caseSensitive: false), '')
        .replaceAll('-', '')
        .toUpperCase();
    return RegExp(r'^[0-9A-F]{32}$').hasMatch(compact) ? compact : null;
  }

  static int _codeLength(String base, String name, String code) {
    for (final length in _lengths.reversed) {
      if (ReceiverNames.stableFallback(
            base,
            'DLNA',
            code,
            codeLength: length,
          ) ==
          name) {
        return length;
      }
    }
    return 0;
  }

  static bool _matchesPeer(String base, String name, String remoteUuid) {
    if (name == base) return true;
    final code = _compactUuid(remoteUuid);
    return code != null && _codeLength(base, name, code) > 0;
  }

  static Map<String, String> _headers(String message) {
    final headers = <String, String>{};
    for (final line in const LineSplitter().convert(message).skip(1)) {
      final separator = line.indexOf(':');
      if (separator > 0) {
        headers[line.substring(0, separator).trim().toUpperCase()] = line
            .substring(separator + 1)
            .trim();
      }
    }
    return headers;
  }

  /// NOTIFY 的 NT 等价于搜索应答中的 ST，归一化后复用既有安全校验。
  static ReceiverSsdpReply? _normalize(ReceiverSsdpReply packet) {
    if (packet.message.length > 8192) return null;
    if (packet.message.startsWith('HTTP/1.1 200')) return packet;
    if (!packet.message.startsWith('NOTIFY * HTTP/1.1')) return null;
    final headers = _headers(packet.message);
    if (![
      'ssdp:alive',
      'ssdp:update',
    ].contains(headers['NTS']?.toLowerCase())) {
      return null;
    }
    return ReceiverSsdpReply(
      sender: packet.sender,
      message:
          'HTTP/1.1 200 OK\r\nST: ${headers['NT'] ?? ''}\r\n'
          'USN: ${headers['USN'] ?? ''}\r\nLOCATION: ${headers['LOCATION'] ?? ''}\r\n\r\n',
    );
  }

  Future<String?> _readDescription(Uri location, Duration timeout) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = false;
    _clients.add(client);
    try {
      return await (() async {
        final request = await client.getUrl(location);
        request.followRedirects = false;
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok ||
            response.contentLength > _maxBytes) {
          return null;
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > _maxBytes) return null;
          bytes.add(chunk);
        }
        return utf8.decode(bytes.takeBytes(), allowMalformed: true);
      })().timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }
}

/// 异步观察携带名称与代际快照，用户改名或服务停止后不应用旧结果。
class _NameObservation {
  const _NameObservation(
    this.location,
    this.remoteUuid,
    this.baseName,
    this.publishedName,
    this.generation,
  );
  final Uri location;
  final String remoteUuid;
  final String baseName;
  final String publishedName;
  final int generation;
}
