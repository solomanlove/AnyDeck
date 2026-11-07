import 'package:flutter/material.dart';

import 'harmony_share_scan_painter.dart';

/// 发现舞台的扫描动画；active 只表示服务正在发现，不代表已发现设备。
/// 自动遵守减少动态效果、无障碍导航与 TickerMode，停止/离页即回收 Ticker。
/// 用法：放入 IgnorePointer/Positioned.fill，传入服务的 scanning 状态。
class HarmonyShareScanBackdrop extends StatefulWidget {
  const HarmonyShareScanBackdrop({super.key, required this.active});

  /// Painter 的最大扩散直径，供外层预留完整绘制范围。
  static const diameter = 790.0;

  final bool active;

  @override
  State<HarmonyShareScanBackdrop> createState() => _ScanBackdropState();
}

class _ScanBackdropState extends State<HarmonyShareScanBackdrop>
    with SingleTickerProviderStateMixin {
  late final _phase = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  bool _animate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _synchronize();
  }

  @override
  void didUpdateWidget(covariant HarmonyShareScanBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronize();
  }

  void _synchronize() {
    _animate =
        widget.active &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    if (_animate) {
      if (!_phase.isAnimating) _phase.repeat();
    } else {
      _phase.stop();
      _phase.value = 0;
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: HarmonyShareScanPainter(
        color: Theme.of(context).colorScheme.primary,
        phase: _phase,
        active: _animate,
      ),
    ),
  );
}
