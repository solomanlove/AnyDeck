import 'dart:async';
import 'dart:io';

/// 鸿蒙投屏会话实体，记录投屏相关状态和长连接进程。
class HarmonyMirrorSession {
  HarmonyMirrorSession({
    required this.deviceId,
    required this.port,
    required this.serverProcess,
    required this.textureId,
    required this.rustHandle,
    required this.startedAt,
    this.width = 1080,
    this.height = 2400,
    this.orientationTimer,
  });

  final String deviceId;
  final int port;
  final Process serverProcess;
  final int textureId;
  final int rustHandle;
  final DateTime startedAt;
  final int width;
  final int height;
  Timer? orientationTimer;
}
