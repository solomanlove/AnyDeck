/// 主仓与私有制品之间的通用 IPC 契约，不包含底层传输协议字段。
abstract final class ShareCoreContract {
  static const version = 2;
  static const maxFileBytes = 1024 * 1024 * 1024;
  static const transferTimeout = Duration(minutes: 30);
}

/// 核心提供的真实传输字节；100% 表示字节阶段完成，任务仍需等待最终成功事件。
class ShareCoreProgress {
  const ShareCoreProgress({
    required this.direction,
    required this.bytes,
    required this.totalBytes,
  });
  final String direction;
  final int bytes;
  final int totalBytes;
  double get fraction => bytes / totalBytes;

  static ShareCoreProgress parse(Map<String, dynamic> event) {
    final direction = event['direction'];
    final bytes = event['bytes'];
    final total = event['total_bytes'];
    if (event['event'] != 'progress' ||
        (direction != 'send' && direction != 'receive') ||
        bytes is! int ||
        total is! int ||
        total < 1 ||
        total > ShareCoreContract.maxFileBytes ||
        bytes < 0 ||
        bytes > total) {
      throw const FormatException('Invalid Share Core progress');
    }
    return ShareCoreProgress(
      direction: direction as String,
      bytes: bytes,
      totalBytes: total,
    );
  }
}
