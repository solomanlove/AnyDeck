import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'performance_charts.dart';
import 'performance_bar_chart.dart';
import 'performance_data.dart';

/// 顶部开机时间和电量状态组件。
class PerformanceTopStatusRow extends StatelessWidget {
  const PerformanceTopStatusRow({
    super.key,
    required this.uptime,
    required this.batteryLevel,
    required this.isCharging,
  });

  final String uptime;
  final int batteryLevel;
  final bool isCharging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.power,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '已开机 $uptime',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xff202124),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                '$batteryLevel%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xff202124),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isCharging
                    ? CupertinoIcons.battery_charging
                    : CupertinoIcons.battery_100,
                size: 20,
                color: isCharging
                    ? const Color(0xff00c853)
                    : const Color(0xff5f6b6e),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 整体 CPU 使用率卡片。
class CpuOverviewCard extends StatelessWidget {
  const CpuOverviewCard({
    super.key,
    required this.overallCpuUsage,
    required this.historyOverallCpu,
  });

  final double overallCpuUsage;
  final List<ChartDataPoint> historyOverallCpu;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffeceef1)),
      ),
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CPU',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xff202124),
                  ),
                ),
                Text(
                  '${overallCpuUsage.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Color(0xff00c853),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: InteractiveLineChart(
                data: historyOverallCpu,
                maxVal: 100,
                lineColor: const Color(0xff00c853),
                fillGradientColors: [
                  const Color(0xff00c853).withValues(alpha: 0.25),
                  const Color(0xff00c853).withValues(alpha: 0.0),
                ],
                windowSize: 90,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CPU 多核心使用率与频率网格组件。
class CpuCoresGrid extends StatelessWidget {
  const CpuCoresGrid({
    super.key,
    required this.cores,
    required this.historyCores,
  });

  final List<CpuCoreSnapshot> cores;
  final Map<int, List<ChartDataPoint>> historyCores;

  @override
  Widget build(BuildContext context) {
    if (cores.isEmpty) return const SizedBox.shrink();

    final width = MediaQuery.of(context).size.width;
    int crossAxisCount = 4;
    if (width < 900) {
      crossAxisCount = 2;
    }
    if (width < 600) {
      crossAxisCount = 1;
    }

    // 动态调整高度使比例适配
    final double childAspectRatio = crossAxisCount == 4
        ? 1.8
        : crossAxisCount == 2
        ? 2.2
        : 3.5;

    final theme = Theme.of(context);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: cores.length,
      itemBuilder: (context, index) {
        final core = cores[index];
        final coreHistory = historyCores[core.id] ?? [];

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xffeceef1)),
          ),
          color: theme.cardColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CPU${core.id} ${core.frequencyMHz.toStringAsFixed(0)}MHz',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Color(0xff5f6b6e),
                      ),
                    ),
                    Text(
                      '${core.usage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xff00c853),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: InteractiveLineChart(
                    data: coreHistory,
                    maxVal: 100,
                    lineColor: const Color(0xff81c784),
                    fillGradientColors: [
                      const Color(0xff81c784).withValues(alpha: 0.15),
                      const Color(0xff81c784).withValues(alpha: 0.0),
                    ],
                    windowSize: 20,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 内存使用率与实际字节卡片。
class MemoryOverviewCard extends StatelessWidget {
  const MemoryOverviewCard({
    super.key,
    required this.memoryUsagePercent,
    required this.usedMemoryMB,
    required this.historyMemory,
  });

  final double memoryUsagePercent;
  final double usedMemoryMB;
  final List<ChartDataPoint> historyMemory;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffeceef1)),
      ),
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '内存 ${memoryUsagePercent.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xff202124),
                  ),
                ),
                Text(
                  '${usedMemoryMB.toStringAsFixed(0)}MB',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Color(0xff7e57c2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: InteractiveLineChart(
                data: historyMemory,
                maxVal: 100,
                lineColor: const Color(0xff7e57c2),
                fillGradientColors: [
                  const Color(0xff7e57c2).withValues(alpha: 0.25),
                  const Color(0xff7e57c2).withValues(alpha: 0.0),
                ],
                windowSize: 90,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// FPS 与前台应用卡片。
class FpsOverviewCard extends StatelessWidget {
  const FpsOverviewCard({
    super.key,
    required this.fps,
    required this.appDisplayName,
    required this.historyFps,
  });

  final double fps;
  final String appDisplayName;
  final List<ChartDataPoint> historyFps;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffeceef1)),
      ),
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'FPS $appDisplayName',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Color(0xff202124),
                    ),
                  ),
                ),
                Text(
                  fps.toStringAsFixed(0),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: Color(0xffff9800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: InteractiveBarChart(
                data: historyFps,
                maxVal: 60,
                barColor: const Color(0xffff9800),
                windowSize: 90,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
