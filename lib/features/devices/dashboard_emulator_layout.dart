part of '../dashboard_screen.dart';

/// 模拟器页标题、分平台 Tab 切换（Android AVD、DevEco Emulator、Xcode Simulator）与操作栏。
class _EmulatorPageLayout extends ConsumerStatefulWidget {
  const _EmulatorPageLayout({
    required this.layoutWidget,
    required this.toolbar,
    required this.filterController,
    required this.onFilterChanged,
  });

  final Widget layoutWidget;
  final Widget toolbar;
  final TextEditingController filterController;
  final ValueChanged<String> onFilterChanged;

  @override
  ConsumerState<_EmulatorPageLayout> createState() => _EmulatorPageLayoutState();
}

class _EmulatorPageLayoutState extends ConsumerState<_EmulatorPageLayout> {
  // 手动选择仅在本次访问生效，重新进入时按最新运行状态选择。
  EmulatorPlatform? _manualPlatform;

  @override
  Widget build(BuildContext context) {
    final selectedPlatform =
        _manualPlatform ??
        ref.watch<EmulatorPlatform>(
          runningEmulatorCountsProvider.select((counts) {
            if (counts.android > 0) return EmulatorPlatform.android;
            if (counts.harmony > 0) return EmulatorPlatform.harmony;
            return counts.ios > 0
                ? EmulatorPlatform.ios
                : EmulatorPlatform.android;
          }),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final search = SizedBox(
          width: compact ? 180 : 220,
          child: TextField(
            controller: widget.filterController,
            style: Theme.of(context).textTheme.bodyMedium,
            onChanged: (val) {
              widget.onFilterChanged(val);
              setState(() {});
            },
            decoration: InputDecoration(
              isDense: true,
              contentPadding: AppThemeSizes.searchFieldContentPadding,
              prefixIconConstraints: AppThemeSizes.searchFieldIconConstraints,
              suffixIconConstraints: AppThemeSizes.searchFieldIconConstraints,
              prefixIcon: const Icon(CupertinoIcons.search, size: 18),
              suffixIcon: widget.filterController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(CupertinoIcons.clear_circled, size: 16),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        widget.filterController.clear();
                        widget.onFilterChanged('');
                        setState(() {});
                      },
                    )
                  : null,
              hintText: context.l10n.t('emulatorSearch'),
              border: const OutlineInputBorder(
                borderRadius: AppThemeSizes.radiusNavigation,
              ),
            ),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部公用标题栏：左侧为标题与副标题，右上角为共用的模拟器平台切换 Tab
            DashboardHeaderBar(
              title: context.l10n.t('emulators'),
              subtitle: context.l10n.t('emulatorsSubtitle'),
              trailing: EmulatorPlatformTabs(
                selectedPlatform: selectedPlatform,
                onPlatformChanged: (platform) {
                  setState(() => _manualPlatform = platform);
                },
              ),
            ),
            // 内容区域：安卓模拟器与其他两端页面保持完全一致（搜索框 + 工具栏 + 分割线 + 表格）
            Expanded(
              child: switch (selectedPlatform) {
                EmulatorPlatform.android => Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
                        child: Row(
                          children: [
                            search,
                            const Spacer(),
                            if (!compact) widget.toolbar,
                          ],
                        ),
                      ),
                      if (compact)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                          child: widget.toolbar,
                        ),
                      const Divider(height: 1),
                      Expanded(child: widget.layoutWidget),
                    ],
                  ),
                EmulatorPlatform.harmony => const DevecoEmulatorsView(),
                EmulatorPlatform.ios => const IosSimulatorsView(),
              },
            ),
          ],
        );
      },
    );
  }
}
