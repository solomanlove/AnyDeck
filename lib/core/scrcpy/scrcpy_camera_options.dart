import 'dart:async';
import 'dart:io';
import 'dart:math';

/// 摄像头固定配置与取消令牌；每次启动独立会话，避免影响同设备屏幕投屏。
class ScrcpyCameraOptions {
  ScrcpyCameraOptions({required String deviceId, required this.front})
    : scid = (Random.secure().nextInt(0x7ffffffe) + 1).toRadixString(16) {
    sessionId = 'camera:$deviceId:$scid';
  }

  final bool front;
  final String scid;
  late final String sessionId;
  bool cancelled = false;
  Process? _process;
  bool _terminating = false;
  Future<void> Function()? removeForward;

  String get socketName => 'scrcpy_${scid.padLeft(8, '0')}';
  List<String> get serverArguments => [
    'video_source=camera',
    'camera_facing=${front ? 'front' : 'back'}',
    'video_codec=h264',
    'camera_fps=30',
    'clipboard_autosync=false',
  ];

  void checkActive() {
    if (cancelled) throw const CameraPreviewException('cameraStopped');
  }

  void attach(Process process) {
    _process = process;
    if (cancelled) _terminate();
  }

  /// 启动尚未完成时也立即停止服务进程；稍后正常清理纹理和转发端口。
  void cancel() {
    cancelled = true;
    _terminate();
  }

  void _terminate() {
    final process = _process;
    if (process == null || _terminating) return;
    _terminating = true;
    process.kill();
    unawaited(
      process.exitCode
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              return -1;
            },
          )
          .catchError((Object _) => -1),
    );
  }
}

class CameraPreviewException implements Exception {
  const CameraPreviewException(this.messageKey);
  final String messageKey;
}
