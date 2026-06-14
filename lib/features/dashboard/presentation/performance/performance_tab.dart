import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/adb/adb_device.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/apps/adb_package.dart';
import 'performance_charts.dart';
import 'performance_data.dart';
import 'performance_widgets.dart';

class PerformanceTab extends ConsumerStatefulWidget {
  const PerformanceTab({
    super.key,
    required this.device,
    required this.isVisible,
  });

  final AdbDevice device;
  final bool isVisible;

  @override
  ConsumerState<PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends ConsumerState<PerformanceTab> {
  Timer? _timer;
  bool _isLoading = true;
  String? _errorMsg;
  bool _wasMirrorWindowOpen = false;

  // 缓存 CPU 计数器状态
  final Map<String, CpuStat> _cpuStats = {};

  // 缓存 FPS 增量参数
  int _prevTotalFrames = 0;
  DateTime? _prevFpsTime;
  double _lastFps = 0.0;

  // 缓存的历史数据集
  final List<ChartDataPoint> _historyOverallCpu = [];
  final Map<int, List<ChartDataPoint>> _historyCores = {};
  final List<ChartDataPoint> _historyMemory = [];
  final List<ChartDataPoint> _historyFps = [];

  // 当前实时指标
  String _uptime = '-';
  int _batteryLevel = 100;
  bool _isCharging = false;
  double _usedMemoryMB = 0;
  double _memoryUsagePercent = 0;
  String _foregroundAppPackage = '';
  double _overallCpuUsage = 0;
  List<CpuCoreSnapshot> _cores = [];
  double _fps = 0;

  // 统一的 ADB Shell 命令文本 (不需要在 Dart 中转义 $)
  // 优化点：不依赖 seq 命令，使用兼容性更好的 for 循环；使用 POSIX case 过滤不合法的包名；增加 || true / ; true 确保命令即使部分没有输出或 grep 未命中也不会返回非零退出码导致判定失败。
  static const String _unifiedCommand =
      r'''focusLine=$(dumpsys window | grep mCurrentFocus || true); cat /proc/uptime; echo "---"; dumpsys battery; echo "---"; cat /proc/meminfo; echo "---"; echo "$focusLine"; echo "---"; cat /proc/stat | grep "^cpu"; echo "---"; for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32; do if [ -d "/sys/devices/system/cpu/cpu$i" ]; then freq_file="/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq"; if [ -f "$freq_file" ]; then cat "$freq_file"; else echo "0"; fi; fi; done; echo "---"; tmp=${focusLine%%/*}; pkg=${tmp##* }; pkg=${pkg##*{}; pkg=${pkg%%\}}; case "$pkg" in *.*) case "$pkg" in *[\{\}\/\=\ ]*) pkg="" ;; esac ;; *) pkg="" ;; esac; if [ -n "$pkg" ]; then dumpsys gfxinfo "$pkg" | grep "Total frames rendered:" || true; fi; true''';


  @override
  void initState() {
    super.initState();
    // 只有在设备在线且当前 Tab 可见时才开启轮询
    if (widget.device.isOnline && widget.isVisible) {
      _startPolling();
    }
  }

  @override
  void didUpdateWidget(covariant PerformanceTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当设备切换、在线状态改变或可见性改变时，重新处理轮询状态
    if (widget.device.id != oldWidget.device.id ||
        widget.device.isOnline != oldWidget.device.isOnline ||
        widget.isVisible != oldWidget.isVisible) {
      _stopPolling();
      // 如果切换了不同的设备，清空历史性能数据
      if (widget.device.id != oldWidget.device.id) {
        _clearHistory();
      }
      // 只有在设备在线且当前性能 tab 可见时才开启轮询
      if (widget.device.isOnline && widget.isVisible) {
        _startPolling();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _isLoading = true;
    _errorMsg = null;
    // 首次立即执行一次
    _pollData();
    // 随后每秒轮询一次
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _pollData());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void _clearHistory() {
    _historyOverallCpu.clear();
    _historyCores.clear();
    _historyMemory.clear();
    _historyFps.clear();
    _cpuStats.clear();
    _prevTotalFrames = 0;
    _prevFpsTime = null;
    _lastFps = 0.0;
  }

  Future<bool> _isMirrorWindowOpen() async {
    try {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (window.arguments.isEmpty) continue;
        try {
          final args = jsonDecode(window.arguments);
          if (args is Map &&
              args['type'] == 'mirror' &&
              args['deviceId'] == widget.device.id) {
            return true;
          }
        } catch (e) {
          debugPrint('Failed to parse window arguments: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to check windows: $e');
    }
    return false;
  }

  Future<void> _pollData() async {
    final isOnline = ref.read(deviceOnlineProvider(widget.device.id));
    // 如果不在线或不可见，停止轮询并返回
    if (!isOnline || !widget.device.isOnline || !widget.isVisible) {
      _stopPolling();
      return;
    }

    final isWindowOpen = await _isMirrorWindowOpen();
    if (isWindowOpen) {
      _wasMirrorWindowOpen = true;
    } else if (_wasMirrorWindowOpen) {
      _stopPolling();
      return;
    }

    try {
      final adb = ref.read(adbServiceProvider);
      final result = await adb.shell(widget.device.id, _unifiedCommand);

      if (!mounted) return;

      if (!result.isSuccess) {
        final errorMsg = (result.stderr + result.stdout).toLowerCase();
        if (errorMsg.contains('not found') || errorMsg.contains('offline')) {
          _stopPolling();
        }
        setState(() {
          _errorMsg = result.stderr.isNotEmpty ? result.stderr : 'ADB 命令执行失败';
          _isLoading = false;
        });
        return;
      }

      final outCpuStats = <String, CpuStat>{};
      final outFpsInfo = <String, double>{};

      final snapshot = PerformanceSnapshot.parse(
        stdout: result.stdout,
        prevCpuStats: _cpuStats,
        outCpuStats: outCpuStats,
        prevTotalFrames: _prevTotalFrames,
        prevFpsTime: _prevFpsTime,
        lastFps: _lastFps,
        outFpsInfo: outFpsInfo,
      );

      // 更新缓存的 CPU 状态计数器
      _cpuStats.addAll(outCpuStats);

      // 更新缓存的 FPS 参数
      _prevTotalFrames = outFpsInfo['totalFrames']?.toInt() ?? 0;
      final cachedTimeMs = outFpsInfo['timestamp']?.toInt();
      if (cachedTimeMs != null) {
        _prevFpsTime = DateTime.fromMillisecondsSinceEpoch(cachedTimeMs);
      }
      _lastFps = snapshot.fps;

      // 生成时间戳 Label (格式 HH:mm:ss)
      final timeStr =
          '${snapshot.timestamp.hour.toString().padLeft(2, '0')}:'
          '${snapshot.timestamp.minute.toString().padLeft(2, '0')}:'
          '${snapshot.timestamp.second.toString().padLeft(2, '0')}';

      // 1. 更新整体 CPU 历史列表
      _historyOverallCpu.add(
        ChartDataPoint(
          value: snapshot.overallCpuUsage,
          label: timeStr,
          timestamp: snapshot.timestamp,
        ),
      );
      if (_historyOverallCpu.length > 90) _historyOverallCpu.removeAt(0);

      // 2. 更新每个核心 CPU 历史列表
      for (final core in snapshot.cores) {
        final list = _historyCores.putIfAbsent(core.id, () => []);
        list.add(
          ChartDataPoint(
            value: core.usage,
            label: timeStr,
            timestamp: snapshot.timestamp,
          ),
        );
        if (list.length > 20) list.removeAt(0);
      }

      // 3. 更新内存历史列表
      _historyMemory.add(
        ChartDataPoint(
          value: snapshot.memoryUsagePercent,
          label: timeStr,
          timestamp: snapshot.timestamp,
        ),
      );
      if (_historyMemory.length > 90) _historyMemory.removeAt(0);

      // 4. 更新 FPS 历史列表
      _historyFps.add(
        ChartDataPoint(
          value: snapshot.fps,
          label: timeStr,
          timestamp: snapshot.timestamp,
        ),
      );
      if (_historyFps.length > 90) _historyFps.removeAt(0);

      setState(() {
        _isLoading = false;
        _errorMsg = null;
        _uptime = snapshot.uptime;
        _batteryLevel = snapshot.batteryLevel;
        _isCharging = snapshot.isCharging;
        _usedMemoryMB = snapshot.usedMemoryMB;
        _memoryUsagePercent = snapshot.memoryUsagePercent;
        _foregroundAppPackage = snapshot.foregroundAppPackage;
        _overallCpuUsage = snapshot.overallCpuUsage;
        _cores = snapshot.cores;
        _fps = snapshot.fps;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));
    if (!isOnline) {
      _stopPolling();
      return Center(
        child: Text(
          context.l10n.t('deviceOffline'),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      );
    }

    if (_isLoading && _historyOverallCpu.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在初始化性能数据面板...', style: TextStyle(color: Color(0xff5f6b6e))),
          ],
        ),
      );
    }

    if (_errorMsg != null && _historyOverallCpu.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                '数据获取失败: $_errorMsg',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(CupertinoIcons.refresh),
                label: const Text('重试连接'),
                onPressed: _startPolling,
              ),
            ],
          ),
        ),
      );
    }

    // 通过包名检索 App 友好的展示名称
    final packagesAsync = ref.watch(packagesProvider(widget.device.id));
    final packageList = packagesAsync.value ?? [];
    final matchedPkg = packageList.firstWhere(
      (p) => p.name == _foregroundAppPackage,
      orElse: () => AdbPackage(name: _foregroundAppPackage, system: false),
    );
    final appDisplayName = matchedPkg.name.isEmpty
        ? '无活动窗口'
        : matchedPkg.displayName;

    return RefreshIndicator(
      onRefresh: _pollData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // 顶部状态栏: 开机时间 + 电量
          PerformanceTopStatusRow(
            uptime: _uptime,
            batteryLevel: _batteryLevel,
            isCharging: _isCharging,
          ),
          const SizedBox(height: 16),

          // CPU 卡片
          CpuOverviewCard(
            overallCpuUsage: _overallCpuUsage,
            historyOverallCpu: _historyOverallCpu,
          ),
          const SizedBox(height: 16),

          // CPU 多核细节网格
          CpuCoresGrid(cores: _cores, historyCores: _historyCores),
          const SizedBox(height: 16),

          // 内存卡片
          MemoryOverviewCard(
            memoryUsagePercent: _memoryUsagePercent,
            usedMemoryMB: _usedMemoryMB,
            historyMemory: _historyMemory,
          ),
          const SizedBox(height: 16),

          // FPS 卡片
          FpsOverviewCard(
            fps: _fps,
            appDisplayName: appDisplayName,
            historyFps: _historyFps,
          ),
        ],
      ),
    );
  }
}
