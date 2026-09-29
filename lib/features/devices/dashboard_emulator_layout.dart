part of '../dashboard_screen.dart';

/// 模拟器完整页面布局；主窗口 Tab 和独立窗口共享标题、操作栏及列表样式。
/// [layoutWidget] 为列表内容，[toolbar] 为当前选择对应的操作按钮。
class _EmulatorStandaloneLayout extends StatelessWidget {
  const _EmulatorStandaloneLayout({
    required this.layoutWidget,
    required this.toolbar,
  });

  final Widget layoutWidget;
  final Widget toolbar;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassBgColor = isDark
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.28);
    final glassBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.04);
    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.03)
        : Colors.white.withValues(alpha: 0.35);

    final tableCard = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: glassBorderColor, width: 1.5),
          ),
          child: layoutWidget,
        ),
      ),
    );

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Container(
        decoration: BoxDecoration(color: glassBgColor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DragToMoveArea(
              child: GlassmorphicContainer(
                width: double.infinity,
                height: 30,
                borderRadius: 0,
                blur: 15,
                alignment: Alignment.center,
                border: 0,
                linearGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.white.withValues(alpha: 0.40),
                    isDark
                        ? Colors.white.withValues(alpha: 0.01)
                        : Colors.white.withValues(alpha: 0.15),
                  ],
                ),
                borderGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.04),
                    isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.black.withValues(alpha: 0.02),
                  ],
                ),
                child: Container(
                  padding: EdgeInsets.only(
                    left: Platform.isMacOS ? 80 : 28,
                    right: 28,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.03),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        context.l10n.t('emulators'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xffeceff1)
                                  : const Color(0xff202124),
                            ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: SizedBox()),
                      toolbar,
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: tableCard),
          ],
        ),
      ),
    );
  }
}
