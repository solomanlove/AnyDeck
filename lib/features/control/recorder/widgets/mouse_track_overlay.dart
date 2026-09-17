import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controller/mouse_track_recorder_controller.dart';
import '../models/recorded_mouse_action.dart';

/// 投屏画面上的鼠标操作轨迹与光标回放轻量级可视化图层。
///
/// 核心特性：
/// 1. **录制时不显示任何轨迹**，保证用户正常交互视野不受干扰；
/// 2. **重放时显示仿真鼠标指针**，跟随录制的操作平滑移动；
/// 3. **按住拖拽时显示当前移动轨迹，抬起点击完后轨迹瞬时消失**；
/// 4. **点击时呈现大范围、长时长的水波涟漪扩散效果**（波纹在原位置优雅荡漾并淡出）；
/// 5. **播放完毕或暂停停止后不显示任何多余轨迹**。
class MouseTrackOverlay extends ConsumerStatefulWidget {
  const MouseTrackOverlay({
    super.key,
    required this.deviceId,
  });

  /// 目标投屏设备 ID
  final String deviceId;

  @override
  ConsumerState<MouseTrackOverlay> createState() => _MouseTrackOverlayState();
}

class _MouseTrackOverlayState extends ConsumerState<MouseTrackOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  /// 当前正在扩散中的水波涟漪集合
  final List<_RippleEffect> _ripples = [];

  /// 记录上一次触发波纹的动作帧索引，防止重复添加
  int _lastRippleActionIndex = -1;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _checkAndSpawnRipple(
    RecordedMouseAction currentAction,
    int currentIndex,
    Size size,
  ) {
    if (currentIndex != _lastRippleActionIndex) {
      _lastRippleActionIndex = currentIndex;
      // 当发生 DOWN 触控动作时，在当前点击绝对位置生成大范围涟漪
      if (currentAction.type == RecordedActionType.down) {
        final pos = Offset(
          currentAction.normX * size.width,
          currentAction.normY * size.height,
        );
        _ripples.add(_RippleEffect(
          origin: pos,
          createdAt: DateTime.now(),
          duration: const Duration(milliseconds: 1000),
        ));
      }
    }

    // 清理已消散的涟漪
    final now = DateTime.now();
    _ripples.removeWhere((r) => now.difference(r.createdAt) > r.duration);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mouseTrackRecorderProvider(widget.deviceId));

    // 非回放状态且无残留波纹时直接隐藏
    if (!state.isPlaying && !state.isPaused) {
      if (_ripples.isNotEmpty) {
        _ripples.clear();
        _lastRippleActionIndex = -1;
      }
      if (_ticker.isAnimating) {
        _ticker.stop();
      }
      return const SizedBox.shrink();
    }

    if (!_ticker.isAnimating) {
      _ticker.repeat();
    }

    final allActions = state.currentTrack?.actions ?? const [];
    final currentIndex = state.playActionIndex.clamp(
      0,
      allActions.isNotEmpty ? allActions.length - 1 : 0,
    );
    final currentAction = state.currentAction;

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (currentAction != null && size.width > 0 && size.height > 0) {
            _checkAndSpawnRipple(currentAction, currentIndex, size);
          }

          return AnimatedBuilder(
            animation: _ticker,
            builder: (context, _) {
              final now = DateTime.now();
              _ripples.removeWhere((r) => now.difference(r.createdAt) > r.duration);

              return CustomPaint(
                size: Size.infinite,
                painter: _MouseTrackReplayPainter(
                  allActions: allActions,
                  currentIndex: currentIndex,
                  currentAction: currentAction,
                  ripples: List.unmodifiable(_ripples),
                  now: now,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 扩散水波对象
class _RippleEffect {
  final Offset origin;
  final DateTime createdAt;
  final Duration duration;

  _RippleEffect({
    required this.origin,
    required this.createdAt,
    required this.duration,
  });

  double progress(DateTime now) {
    final diff = now.difference(createdAt).inMilliseconds;
    return (diff / duration.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// 鼠标回放轨迹、鼠标指针与长时大范围点击扩散画板
class _MouseTrackReplayPainter extends CustomPainter {
  const _MouseTrackReplayPainter({
    required this.allActions,
    required this.currentIndex,
    required this.currentAction,
    required this.ripples,
    required this.now,
  });

  final List<RecordedMouseAction> allActions;
  final int currentIndex;
  final RecordedMouseAction? currentAction;
  final List<_RippleEffect> ripples;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || currentAction == null) return;

    // 1. 寻找当前处于按压拖拽中的这“单次笔划”（从最近的 DOWN 开始）
    // 规则：抬起点击完毕后，上一笔轨迹自动消失
    int currentStrokeDownIndex = -1;
    for (int i = currentIndex; i >= 0; i--) {
      if (allActions[i].type == RecordedActionType.down) {
        currentStrokeDownIndex = i;
        break;
      }
      if (allActions[i].type == RecordedActionType.up ||
          allActions[i].type == RecordedActionType.cancel) {
        // 先遇到抬起，说明当前不处于手势按压滑动中
        break;
      }
    }

    // 仅在当前正处于按压移动阶段时，绘制当前这一笔的轨迹线
    if (currentStrokeDownIndex != -1 &&
        currentAction!.type != RecordedActionType.up &&
        currentAction!.type != RecordedActionType.cancel) {
      final strokeActions = allActions.sublist(
        currentStrokeDownIndex,
        currentIndex + 1,
      );

      final linePaint = Paint()
        ..color = const Color(0xAA00E5FF)
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      Path? strokePath;
      for (int i = 0; i < strokeActions.length; i++) {
        final act = strokeActions[i];
        final pt = Offset(act.normX * size.width, act.normY * size.height);
        if (i == 0) {
          strokePath = Path()..moveTo(pt.dx, pt.dy);
          // 起始按压小圆点
          canvas.drawCircle(
            pt,
            3.5,
            Paint()
              ..color = const Color(0xEE00E5FF)
              ..style = PaintingStyle.fill,
          );
        } else {
          strokePath?.lineTo(pt.dx, pt.dy);
        }
      }

      if (strokePath != null) {
        canvas.drawPath(strokePath, linePaint);
      }
    }

    // 2. 绘制大范围、长时长的水波涟漪（点击处原地扩散并优雅淡出）
    for (final ripple in ripples) {
      final p = ripple.progress(now);
      if (p >= 1.0) continue;

      // 第一层大波纹（半径从 5 扩大到 54）
      final r1 = lerpDouble(5.0, 54.0, Curves.easeOutCubic.transform(p)) ?? 30.0;
      final alpha1 = ((1.0 - p) * 0.85 * 255).clamp(0, 255).toInt();
      final ripplePaint1 = Paint()
        ..color = Color.fromARGB(alpha1, 0, 229, 255)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lerpDouble(2.5, 1.0, p) ?? 1.5;
      canvas.drawCircle(ripple.origin, r1, ripplePaint1);

      // 第二层跟随小波纹（半径从 4 扩大到 36）
      final p2 = (p + 0.25).clamp(0.0, 1.0);
      final r2 = lerpDouble(4.0, 36.0, Curves.easeOutCubic.transform(p2)) ?? 20.0;
      final alpha2 = ((1.0 - p) * 0.45 * 255).clamp(0, 255).toInt();
      final ripplePaint2 = Paint()
        ..color = Color.fromARGB(alpha2, 0, 255, 180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(ripple.origin, r2, ripplePaint2);

      // 核心微弱光晕
      final glowAlpha = ((1.0 - p) * 0.35 * 255).clamp(0, 255).toInt();
      canvas.drawCircle(
        ripple.origin,
        lerpDouble(3.0, 14.0, p) ?? 8.0,
        Paint()
          ..color = Color.fromARGB(glowAlpha, 0, 229, 255)
          ..style = PaintingStyle.fill,
      );
    }

    // 3. 绘制仿真鼠标指针（箭头）
    final mouseTip = Offset(
      currentAction!.normX * size.width,
      currentAction!.normY * size.height,
    );
    final isPressing = currentAction!.type == RecordedActionType.down ||
        (currentAction!.type == RecordedActionType.move &&
            currentAction!.pressure > 0.1);

    _drawMouseCursor(canvas, mouseTip, isPressing: isPressing);
  }

  void _drawMouseCursor(Canvas canvas, Offset tip, {required bool isPressing}) {
    canvas.save();
    canvas.translate(tip.dx, tip.dy);

    if (isPressing) {
      canvas.scale(0.92);
    }

    // 鼠标指针矢量轮廓（尖端在 0, 0）
    final cursorPath = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 17)
      ..lineTo(4.5, 13.5)
      ..lineTo(8, 20.5)
      ..lineTo(11, 19)
      ..lineTo(7.5, 12)
      ..lineTo(13, 12)
      ..close();

    // 投影
    final shadowPaint = Paint()
      ..color = const Color(0x59000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.save();
    canvas.translate(1.5, 2.0);
    canvas.drawPath(cursorPath, shadowPaint);
    canvas.restore();

    // 白色填充
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(cursorPath, fillPaint);

    // 黑色描边
    final borderPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(cursorPath, borderPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MouseTrackReplayPainter oldDelegate) {
    return true; // 随水波扩散动画每帧流畅重绘
  }
}
