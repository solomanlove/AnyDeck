import 'dart:math';
import 'package:flutter/material.dart';

/// 一个轻量级、高性能的动态液态渐变背景。
/// 底层使用 3 个缓慢做简谐运动（振荡和绕轨）的彩色径向渐变大球，
/// 在配合上层毛玻璃模糊（BackdropFilter）时，会融合成极其自然丝滑的液态折射效果。
class LiquidGlassBackground extends StatefulWidget {
  const LiquidGlassBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<LiquidGlassBackground> createState() => _LiquidGlassBackgroundState();
}

class _LiquidGlassBackgroundState extends State<LiquidGlassBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 15 秒一周，超长平滑周期以确保肉眼不可察觉的卡顿且占用极低 CPU
    _controller = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 根据亮暗主题自适应底色
    final baseColor = isDark ? const Color(0xff0b0d10) : const Color(0xfff4f6f8);

    // 自适应球体不透明度：暗色可以亮一些，亮色必须非常淡以防刺眼
    final double opacityFactor = isDark ? 0.9 : 0.6;

    return Stack(
      children: [
        // 1. 底色
        Positioned.fill(
          child: Container(
            color: baseColor,
          ),
        ),
        // 2. 动态液态泡泡 (通过 AnimatedBuilder 精确驱动)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final double value = _controller.value;
              final double rad = value * 2 * pi;

              // 气泡 1 轨迹 (左上角摆动)
              final x1 = 120.0 + 70.0 * sin(rad);
              final y1 = 150.0 + 80.0 * cos(rad * 0.9);

              // 气泡 2 轨迹 (右下角摆动)
              final x2 = MediaQuery.of(context).size.width - 240.0 - 90.0 * cos(rad + pi / 3);
              final y2 = MediaQuery.of(context).size.height - 240.0 - 60.0 * sin(rad * 1.1 + pi);

              // 气泡 3 轨迹 (底部中央摆动)
              final x3 = MediaQuery.of(context).size.width / 2 - 120.0 + 100.0 * cos(rad * 0.8 + pi / 4);
              final y3 = 250.0 + 100.0 * sin(rad * 0.7);

              return Stack(
                children: [
                  // 气泡 1：青色
                  Positioned(
                    left: x1,
                    top: y1,
                    child: Container(
                      width: 380,
                      height: 380,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xff00f2fe).withValues(alpha: 0.18 * opacityFactor),
                            const Color(0xff00f2fe).withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 气泡 2：粉紫色
                  Positioned(
                    left: x2,
                    top: y2,
                    child: Container(
                      width: 420,
                      height: 420,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xffe0c3fc).withValues(alpha: 0.22 * opacityFactor),
                            const Color(0xff8ec5fc).withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 气泡 3：暖阳橙
                  Positioned(
                    left: x3,
                    top: y3,
                    child: Container(
                      width: 320,
                      height: 320,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xfffecfef).withValues(alpha: 0.16 * opacityFactor),
                            const Color(0xffff9a9e).withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // 3. 上层内容区域
        Positioned.fill(child: widget.child),
      ],
    );
  }
}
