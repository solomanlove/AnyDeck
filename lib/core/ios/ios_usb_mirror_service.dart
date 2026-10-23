import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../logging/app_log_recorder.dart';

/// macOS 原生 USB 采集桥接；返回 Texture ID，不经过 Dart 图像拷贝或 MJPEG。
class IosUsbMirrorService {
  static const channel = MethodChannel('anydeck/ios_usb_capture');
  final Map<String, int> _textures = {};
  final Map<String, Future<int>> _starting = {};
  int? texture(String udid) => _textures[udid];

  Future<int> start(String udid, {bool audioEnabled = true}) {
    if (!Platform.isMacOS) throw UnsupportedError('iosUsbMacOnly');
    if (_textures[udid] case final id?) {
      unawaited(setGlobalAudioEnabled(audioEnabled, udid: udid));
      return Future.value(id);
    }
    return _starting.putIfAbsent(
      udid,
      () => _start(udid, audioEnabled: audioEnabled),
    );
  }

  /// 动态更新当前窗口引擎内 iOS USB 采集的音频转发开关。
  static Future<void> setGlobalAudioEnabled(
    bool enabled, {
    String? udid,
  }) async {
    if (!Platform.isMacOS) return;
    try {
      await channel.invokeMethod<void>('setAudioEnabled', {
        'audioEnabled': enabled,
        'udid': ?udid,
      });
    } catch (_) {}
  }

  Future<int> _start(String udid, {required bool audioEnabled}) async {
    try {
      AppLogRecorder.instance.record(
        'USB capture start: $udid (audio=$audioEnabled)',
        tag: 'ios-video',
      );
      final id = await channel.invokeMethod<int>('start', {
        'udid': udid,
        'audioEnabled': audioEnabled,
      });
      if (id == null || id == 0) throw StateError('iosUsbTextureFailed');
      _textures[udid] = id;
      AppLogRecorder.instance.record(
        'USB first frame ready; texture=$id',
        tag: 'ios-video',
      );
      return id;
    } catch (error) {
      AppLogRecorder.instance.record(
        'USB capture failed: $error',
        tag: 'ios-video',
        level: 'E',
      );
      rethrow;
    } finally {
      _starting.remove(udid);
    }
  }

  Future<Map<String, dynamic>> status(String udid) async =>
      Map<String, dynamic>.from(
        await channel.invokeMapMethod<String, dynamic>('status', {
              'udid': udid,
            }) ??
            {},
      );

  Future<void> stop(String udid) async {
    if (!_textures.containsKey(udid) && !_starting.containsKey(udid)) return;
    _textures.remove(udid);
    await channel.invokeMethod<void>('stop', {'udid': udid});
    // 原生 stop 会取消尚未收到首帧的启动请求，避免迟到结果复活已关闭会话。
    try {
      await _starting[udid];
    } catch (_) {}
    _textures.remove(udid);
  }

  void stopAll() {
    for (final udid in {..._textures.keys, ..._starting.keys}) {
      stop(udid);
    }
  }
}
