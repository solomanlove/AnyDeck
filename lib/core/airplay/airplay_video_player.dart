import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 将 AirPlay HTTP 视频目标状态串行应用到独立的原生媒体窗口。
/// 复用 DLNA 的 AVPlayer 窗口实现，但不共享 DLNA 的会话和控制通道。
class AirPlayVideoPlayer {
  AirPlayVideoPlayer({required this.read, required this.report});

  final Map<String, dynamic>? Function(int) read;
  final void Function(int, int, Map<dynamic, dynamic>) report;
  static const channel = MethodChannel('any_deck/airplay_player');
  int? _handle;
  int _epoch = 0;
  int _generation = -1;
  int _windowGeneration = 0;
  int _revision = -1;
  int _seekRevision = -1;
  bool _active = false;
  bool _busy = false;
  bool _pinned = false;
  String _title = 'AirPlay';
  String _loadingText = '';
  String _failureText = '';
  Timer? _timer;
  Future<void>? _inflight;

  Future<void> _invoke(String method, [Object? arguments]) => channel
      .invokeMethod<void>(method, arguments)
      .timeout(const Duration(seconds: 3));

  /// 由接收服务拥有生命周期；重启时先等旧操作收尾，避免旧窗口回调结束新视频。
  Future<void> start(int handle, String title) async {
    await stop();
    _handle = handle;
    _title = title;
    channel.setMethodCallHandler(_onEvent);
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) => poll());
  }

  Future<void> setLabels({
    required String loading,
    required String failure,
    required String pin,
    required String unpin,
  }) async {
    _loadingText = loading;
    _failureText = failure;
    await _invoke('setLoadingText', loading);
    await _invoke('setFailureText', failure);
    await _invoke('setPinLabels', {'pin': pin, 'unpin': unpin});
  }

  Future<void> _onEvent(MethodCall call) async {
    final args = call.arguments;
    if (call.method == 'pinChanged' && args is bool) {
      _pinned = args;
    } else if (_active &&
        args is Map &&
        args['generation'] == _windowGeneration &&
        call.method == 'playerStopped') {
      report(_handle!, _generation, {'state': 2});
      _active = false;
      _pinned = false;
    } else if (call.method == 'playerFailed' &&
        args is Map &&
        args['generation'] == _windowGeneration) {
      // 原生窗口保留本地化错误；快照会把失败状态同步给手机。
      debugPrint('[AirPlay Video] player failed: ${args['detail']}');
    }
  }

  /// 单飞轮询，合并加载期间的控制请求，不积累无界消息队列。
  Future<void> poll() {
    if (_busy || _handle == null) return Future<void>.value();
    _busy = true;
    final work = _poll(_epoch).whenComplete(() => _busy = false);
    _inflight = work;
    return work;
  }

  Future<void> _poll(int epoch) async {
    final handle = _handle!;
    int? requestedGeneration;
    try {
      final command = read(handle);
      if (command == null || epoch != _epoch) return;
      final generation = command['generation'] as int;
      requestedGeneration = generation;
      final revision = command['revision'] as int;
      final seekRevision = command['seek_revision'] as int;
      final url = command['url'] as String?;
      if (revision != _revision) {
        if (url == null) {
          if (_active) await _invoke('close');
          _active = false;
          _pinned = false;
        } else {
          final uri = Uri.tryParse(url);
          if (uri == null ||
              !const ['http', 'https'].contains(uri.scheme) ||
              uri.host.isEmpty) {
            throw const FormatException('Invalid AirPlay media URL');
          }
          if (generation != _generation) {
            _generation = generation;
            _windowGeneration++;
            _active = true;
            await _invoke('setTitle', _title);
            if (epoch != _epoch) return;
            await _invoke('playUrl', {
              'url': url,
              'generation': _windowGeneration,
              'position': (command['start'] as num).toDouble(),
              'rate': (command['rate'] as num).toDouble(),
              'loadingText': _loadingText,
              'failureText': _failureText,
              'alwaysOnTop': _pinned,
            });
            debugPrint('[AirPlay Video] opened generation=$generation');
          } else if (_active) {
            if (seekRevision != _seekRevision) {
              await _invoke('seek', (command['start'] as num).toDouble());
            }
            if (epoch != _epoch) return;
            await _invoke('setRate', (command['rate'] as num).toDouble());
          }
        }
        if (epoch != _epoch) return;
        _revision = revision;
        _seekRevision = seekRevision;
      }
      if (_active) {
        final actual = await channel
            .invokeMapMethod<dynamic, dynamic>('playbackState')
            .timeout(const Duration(seconds: 3));
        if (actual != null &&
            epoch == _epoch &&
            actual['generation'] == _windowGeneration) {
          report(handle, generation, actual);
          // 失败保留窗口供用户阅读；收到下一条 Stop/Play 时再关闭或替换。
          if (actual['state'] == 2) _active = false;
        }
      }
    } catch (error) {
      if (epoch != _epoch) return;
      // 不输出可能含签名或鉴权参数的原始 URL/平台异常。
      debugPrint('[AirPlay Video] command failed (${error.runtimeType})');
      if (requestedGeneration != null) {
        report(handle, requestedGeneration, {'state': 2});
      }
      _active = false;
      try {
        await _invoke('close');
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _epoch++;
    _timer?.cancel();
    _timer = null;
    _handle = null;
    _active = false;
    await _inflight;
    _inflight = null;
    _generation = -1;
    _revision = -1;
    _seekRevision = -1;
    _pinned = false;
    try {
      await _invoke('close');
    } catch (_) {}
  }
}
