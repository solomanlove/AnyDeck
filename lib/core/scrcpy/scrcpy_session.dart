/// 应用启动的单个 scrcpy 进程运行时元数据。
class ScrcpySession {
  const ScrcpySession({
    required this.id,
    required this.deviceId,
    required this.pid,
    required this.startedAt,
  });

  final String id;
  final String deviceId;
  final int pid;
  final DateTime startedAt;
}
