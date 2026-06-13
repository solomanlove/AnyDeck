import 'dart:math';

/// 单个 CPU 核心的性能采样快照。
class CpuCoreSnapshot {
  const CpuCoreSnapshot({
    required this.id,
    required this.usage,
    required this.frequencyMHz,
  });

  final int id;
  final double usage; // 0.0 - 100.0
  final double frequencyMHz;
}

/// 整体 CPU 状态计数器，用于通过两次差值计算使用率。
class CpuStat {
  const CpuStat({
    required this.idle,
    required this.nonIdle,
    required this.total,
  });

  factory CpuStat.parse(String line) {
    final parts = line
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 5) {
      return const CpuStat(idle: 0, nonIdle: 0, total: 0);
    }
    // parts[0] 为 cpu/cpu0/cpu1 等
    final user = int.tryParse(parts[1]) ?? 0;
    final nice = int.tryParse(parts[2]) ?? 0;
    final system = int.tryParse(parts[3]) ?? 0;
    final idleTime = int.tryParse(parts[4]) ?? 0;
    final iowait = parts.length > 5 ? (int.tryParse(parts[5]) ?? 0) : 0;
    final irq = parts.length > 6 ? (int.tryParse(parts[6]) ?? 0) : 0;
    final softirq = parts.length > 7 ? (int.tryParse(parts[7]) ?? 0) : 0;
    final steal = parts.length > 8 ? (int.tryParse(parts[8]) ?? 0) : 0;

    final idle = idleTime + iowait;
    final nonIdle = user + nice + system + irq + softirq + steal;
    final total = idle + nonIdle;

    return CpuStat(idle: idle, nonIdle: nonIdle, total: total);
  }

  final int idle;
  final int nonIdle;
  final int total;
}

/// 某一个瞬间的整机性能性能采样。
class PerformanceSnapshot {
  const PerformanceSnapshot({
    required this.uptime,
    required this.batteryLevel,
    required this.isCharging,
    required this.totalMemoryMB,
    required this.usedMemoryMB,
    required this.memoryUsagePercent,
    required this.foregroundAppPackage,
    required this.overallCpuUsage,
    required this.cores,
    required this.totalFrames,
    required this.fps,
    required this.timestamp,
  });

  final String uptime;
  final int batteryLevel;
  final bool isCharging;
  final double totalMemoryMB;
  final double usedMemoryMB;
  final double memoryUsagePercent;
  final String foregroundAppPackage;
  final double overallCpuUsage;
  final List<CpuCoreSnapshot> cores;
  final int totalFrames;
  final double fps;
  final DateTime timestamp;

  /// 解析统一的 shell 输出文本并计算增量。
  static PerformanceSnapshot parse({
    required String stdout,
    required Map<String, CpuStat> prevCpuStats,
    required Map<String, CpuStat> outCpuStats, // 用于向外传递当前 CPU 计数器状态
    required int prevTotalFrames,
    required DateTime? prevFpsTime,
    required double lastFps,
    required Map<String, double> outFpsInfo, // 用于向外传递帧数和时间戳缓存
  }) {
    final sections = stdout.split('\n---\n');
    final timestamp = DateTime.now();

    // 默认空/回退值
    String uptime = '-';
    int batteryLevel = 100;
    bool isCharging = false;
    double totalMemoryMB = 0;
    double usedMemoryMB = 0;
    double memoryUsagePercent = 0;
    String foregroundAppPackage = '';
    double overallCpuUsage = 0;
    final List<CpuCoreSnapshot> cores = [];
    int totalFrames = 0;
    double fps = 0;

    // 1. 解析 Uptime (Section 0)
    if (sections.isNotEmpty) {
      final line = sections[0].trim();
      if (line.isNotEmpty) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.isNotEmpty) {
          final seconds = double.tryParse(parts[0]) ?? 0.0;
          if (seconds > 0) {
            final int totalSecs = seconds.toInt();
            final int days = totalSecs ~/ 86400;
            final int hours = (totalSecs % 86400) ~/ 3600;
            final int minutes = (totalSecs % 3600) ~/ 60;
            final int secs = totalSecs % 60;
            uptime =
                '${days > 0 ? '$days:' : ''}'
                '${hours.toString().padLeft(2, '0')}:'
                '${minutes.toString().padLeft(2, '0')}:'
                '${secs.toString().padLeft(2, '0')}';
          }
        }
      }
    }

    // 2. 解析 Battery (Section 1)
    if (sections.length > 1) {
      final lines = sections[1].split('\n');
      for (final line in lines) {
        if (line.contains('level:')) {
          batteryLevel = int.tryParse(line.split(':').last.trim()) ?? 100;
        } else if (line.contains('status:')) {
          final status = int.tryParse(line.split(':').last.trim()) ?? 1;
          isCharging = (status == 2 || status == 5);
        } else if (line.contains('powered: true')) {
          isCharging = true;
        }
      }
    }

    // 3. 解析 Memory (Section 2)
    if (sections.length > 2) {
      final lines = sections[2].split('\n');
      double availableMemoryMB = 0;
      for (final line in lines) {
        if (line.startsWith('MemTotal:')) {
          final val = RegExp(r'\d+').stringMatch(line);
          if (val != null) {
            totalMemoryMB = (double.tryParse(val) ?? 0) / 1024.0;
          }
        } else if (line.startsWith('MemAvailable:')) {
          final val = RegExp(r'\d+').stringMatch(line);
          if (val != null) {
            availableMemoryMB = (double.tryParse(val) ?? 0) / 1024.0;
          }
        }
      }
      if (availableMemoryMB == 0) {
        double free = 0;
        double cached = 0;
        double buffers = 0;
        for (final line in lines) {
          if (line.startsWith('MemFree:')) {
            final val = RegExp(r'\d+').stringMatch(line);
            if (val != null) free = (double.tryParse(val) ?? 0) / 1024.0;
          } else if (line.startsWith('Cached:')) {
            final val = RegExp(r'\d+').stringMatch(line);
            if (val != null) cached = (double.tryParse(val) ?? 0) / 1024.0;
          } else if (line.startsWith('Buffers:')) {
            final val = RegExp(r'\d+').stringMatch(line);
            if (val != null) buffers = (double.tryParse(val) ?? 0) / 1024.0;
          }
        }
        availableMemoryMB = free + cached + buffers;
      }
      usedMemoryMB = max(0, totalMemoryMB - availableMemoryMB);
      memoryUsagePercent = totalMemoryMB > 0
          ? (usedMemoryMB / totalMemoryMB * 100.0)
          : 0;
    }

    // 4. 解析 前台应用 (Section 3)
    if (sections.length > 3) {
      final focusLine = sections[3].trim();
      if (focusLine.isNotEmpty && !focusLine.contains('mCurrentFocus=null')) {
        final tmp = focusLine.split('/').first;
        final parts = tmp
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) {
          var pkg = parts.last;
          if (pkg.contains('{')) {
            pkg = pkg.split('{').last;
          }
          if (pkg.contains('}')) {
            pkg = pkg.split('}').first;
          }
          if (!pkg.contains('=')) {
            foregroundAppPackage = pkg;
          }
        }
      }
    }

    // 5. 解析 CPU Frequencies (Section 5)
    // 提前拿到频率列表，方便在解析 Section 4 时注入每个 Core 的 Freq。
    final List<double> frequenciesMHz = [];
    if (sections.length > 5) {
      final lines = sections[5]
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      for (final line in lines) {
        final khz = double.tryParse(line) ?? 0.0;
        frequenciesMHz.add(khz / 1000.0);
      }
    }

    // 6. 解析 CPU /proc/stat (Section 4)
    if (sections.length > 4) {
      final lines = sections[4]
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      for (final line in lines) {
        final match = RegExp(r'^(cpu[0-9]*)\s+').firstMatch(line);
        if (match != null) {
          final key = match.group(1)!;
          final currentStat = CpuStat.parse(line);
          outCpuStats[key] = currentStat;

          final prevStat = prevCpuStats[key];
          double usage = 0.0;
          if (prevStat != null) {
            final totalDelta = currentStat.total - prevStat.total;
            final idleDelta = currentStat.idle - prevStat.idle;
            if (totalDelta > 0) {
              usage = (totalDelta - idleDelta) / totalDelta * 100.0;
              usage = usage.clamp(0.0, 100.0);
            }
          }

          if (key == 'cpu') {
            overallCpuUsage = usage;
          } else {
            final coreId = int.tryParse(key.replaceAll('cpu', '')) ?? 0;
            final freq = coreId < frequenciesMHz.length
                ? frequenciesMHz[coreId]
                : 0.0;
            cores.add(
              CpuCoreSnapshot(id: coreId, usage: usage, frequencyMHz: freq),
            );
          }
        }
      }
    }

    // 7. 解析 FPS (Section 6)
    if (sections.length > 6) {
      final gfxLine = sections[6].trim();
      final match = RegExp(
        r'Total frames rendered:\s*(\d+)',
      ).firstMatch(gfxLine);
      if (match != null) {
        totalFrames = int.tryParse(match.group(1)!) ?? 0;
      }
    }

    // 计算 FPS
    if (totalFrames > 0 && prevTotalFrames > 0 && prevFpsTime != null) {
      final frameDelta = totalFrames - prevTotalFrames;
      final timeDeltaMs = timestamp.difference(prevFpsTime).inMilliseconds;
      if (timeDeltaMs > 0 && frameDelta >= 0) {
        fps = frameDelta / (timeDeltaMs / 1000.0);
        fps = fps.clamp(0.0, 120.0); // 绝大多数屏幕上限 120
      } else {
        fps = lastFps;
      }
    } else {
      fps = totalFrames > 0 ? 0.0 : 0.0;
    }

    // 将当前的帧数和时间戳更新回 outFpsInfo
    outFpsInfo['totalFrames'] = totalFrames.toDouble();
    outFpsInfo['timestamp'] = timestamp.millisecondsSinceEpoch.toDouble();

    // 核心数降序排列或升序
    cores.sort((a, b) => a.id.compareTo(b.id));

    return PerformanceSnapshot(
      uptime: uptime,
      batteryLevel: batteryLevel,
      isCharging: isCharging,
      totalMemoryMB: totalMemoryMB,
      usedMemoryMB: usedMemoryMB,
      memoryUsagePercent: memoryUsagePercent,
      foregroundAppPackage: foregroundAppPackage,
      overallCpuUsage: overallCpuUsage,
      cores: cores,
      totalFrames: totalFrames,
      fps: fps,
      timestamp: timestamp,
    );
  }
}
