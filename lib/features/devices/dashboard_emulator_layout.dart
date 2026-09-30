part of '../dashboard_screen.dart';

/// 模拟器页标题、搜索与操作栏。窄窗口分两行，独立窗口单独预留系统按钮空间。
class _EmulatorStandaloneLayout extends StatelessWidget {
  const _EmulatorStandaloneLayout({
    required this.layoutWidget,
    required this.toolbar,
    required this.isEmbeddedTab,
    required this.filterController,
    required this.onFilterChanged,
  });

  final Widget layoutWidget;
  final Widget toolbar;
  final bool isEmbeddedTab;
  final TextEditingController filterController;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1100;
        final search = SizedBox(
          width: compact ? 180 : 220,
          child: TextField(
            controller: filterController,
            onChanged: onFilterChanged,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(CupertinoIcons.search, size: 18),
              hintText: context.l10n.t('emulatorSearch'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isEmbeddedTab && Platform.isMacOS)
              const DragToMoveArea(child: SizedBox(height: 30)),
            DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: 72,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.t('emulators'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 16),
                      search,
                      if (!compact) ...[const SizedBox(width: 16), toolbar],
                    ],
                  ),
                ),
              ),
            ),
            if (compact)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: toolbar,
              ),
            const Divider(height: 1),
            Expanded(child: layoutWidget),
          ],
        );
      },
    );
  }
}
