/// 从已有的 /proc/meminfo 查询结果解析总内存与当前已用内存。
class DeviceMemoryInfo {
  const DeviceMemoryInfo({required this.totalKb, this.usedKb});

  final int? totalKb;
  final int? usedKb;

  String get total => _formatGb(totalKb);
  String get used => _formatGb(usedKb);

  static DeviceMemoryInfo parse(String output) {
    final fields = <String, int>{
      for (final match in RegExp(
        r'^(\w+):\s*(\d+)\s+kB\s*$',
        multiLine: true,
      ).allMatches(output))
        match.group(1)!: int.parse(match.group(2)!),
    };
    final total = fields['MemTotal'];
    if (total == null || total <= 0) {
      return const DeviceMemoryInfo(totalKb: null);
    }

    // 优先扣除内核估算的可用内存，避免把可回收缓存全部算作已用。
    var available = fields['MemAvailable'];
    if (available == null) {
      final free = fields['MemFree'];
      final buffers = fields['Buffers'];
      final cached = fields['Cached'];
      // 旧内核缺少 MemAvailable 时使用缓存估算；字段不足则不伪造占用。
      if (free != null && buffers != null && cached != null) {
        available =
            free +
            buffers +
            cached +
            (fields['SReclaimable'] ?? 0) -
            (fields['Shmem'] ?? 0);
      }
    }
    return DeviceMemoryInfo(
      totalKb: total,
      usedKb: available == null ? null : total - available.clamp(0, total),
    );
  }

  static String _formatGb(int? kb) =>
      kb == null ? '-' : '${(kb / (1024 * 1024)).toStringAsFixed(2)}G';
}
