import 'dart:io';

/// iOS 屏幕投屏会话，保存 go-ios 进程句柄和本地流端口。
class IosMirrorSession {
  IosMirrorSession({
    required this.udid,
    required this.port,
    required this.process,
    required this.startedAt,
  });

  final String udid;
  final int port;
  final Process process;
  final DateTime startedAt;
}
