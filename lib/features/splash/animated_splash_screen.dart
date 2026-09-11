import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/window/desktop_window_manager_service.dart';
import '../dashboard_screen.dart';

/// 应用启动动效屏与主界面平滑过渡组件。
///
/// 核心职责：
/// 1. 窗口渲染首帧完成后，通知窗口管理器显示窗口，彻底消除黑屏闪烁；
/// 2. 播放品牌 Logo 缩放渐入、标语滑入与加载进度动效；
/// 3. 并行静默预热主面板（DashboardScreen），动效完成后平滑淡出揭开主界面。
class AnimatedSplashScreen extends ConsumerStatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  ConsumerState<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends ConsumerState<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScaleAnimation;
  late final Animation<double> _logoFadeAnimation;
  late final Animation<Offset> _contentSlideAnimation;
  late final Animation<double> _contentFadeAnimation;
  late final Animation<double> _progressAnimation;

  /// 标记启动动画是否已完成，用于触发淡出过渡
  bool _isStartupComplete = false;

  /// 标记启动层是否已彻底从 Widget 树中卸载，释放动画控制器等资源
  bool _isSplashDisposed = false;

  @override
  void initState() {
    super.initState();

    // 动画总时长约为 1000ms
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // 1. Logo 弹性缩放与渐显
    _logoScaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutBack),
      ),
    );
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
      ),
    );

    // 2. 标语与文字滑入渐显
    _contentSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.85, curve: Curves.easeOutCubic),
      ),
    );
    _contentFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.85, curve: Curves.easeIn),
      ),
    );

    // 3. 极简进度条加载动画
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.95, curve: Curves.easeInOutCubic),
      ),
    );

    // 首帧绘制完成后，通知桌面窗口管理器显示窗口（此时画面已就绪，零黑屏）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DesktopWindowManagerService.showWindow();
    });

    // 启动动画序列并安排转场
    _startAnimationSequence();
  }

  Future<void> _startAnimationSequence() async {
    // 播放入场动画
    await _controller.forward();

    // 稍作短暂停留（150ms），确保视觉节奏舒适自然
    await Future.delayed(const Duration(milliseconds: 150));

    if (!mounted) return;

    // 触发启动层渐变淡出
    setState(() {
      _isStartupComplete = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. 底层主面板（提前预热并在启动淡出后完整呈现）
        const DashboardScreen(),

        // 2. 顶层品牌动效层（淡出完成后自动卸载，不截断事件）
        if (!_isSplashDisposed)
          IgnorePointer(
            ignoring: _isStartupComplete,
            child: AnimatedOpacity(
              opacity: _isStartupComplete ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              onEnd: () {
                if (mounted && _isStartupComplete) {
                  setState(() {
                    _isSplashDisposed = true;
                  });
                }
              },
              child: _buildSplashContent(context),
            ),
          ),
      ],
    );
  }

  /// 构建启动画面主体 UI
  Widget _buildSplashContent(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 自适应背景色，与整体桌面主题相融
    final backgroundColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFF7F8FA);

    return Material(
      color: backgroundColor,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 品牌 Logo 缩放渐入
                FadeTransition(
                  opacity: _logoFadeAnimation,
                  child: ScaleTransition(
                    scale: _logoScaleAnimation,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.35 : 0.08,
                            ),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/brand/app_logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 2. 标题与 Slogan 滑入渐显
                SlideTransition(
                  position: _contentSlideAnimation,
                  child: FadeTransition(
                    opacity: _contentFadeAnimation,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l10n.t('appTitle'),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.l10n.t('appSlogan'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 36),

                // 3. 科技感加载条与状态小字
                FadeTransition(
                  opacity: _contentFadeAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 140,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: _progressAnimation.value,
                            minHeight: 3,
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.t('startingUp'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
