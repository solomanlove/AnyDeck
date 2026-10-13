part of '../dashboard_screen.dart';

/// 模拟器页标题、分平台 Tab 切换（Android AVD、DevEco Emulator、Xcode Simulator）与操作栏。
class _EmulatorStandaloneLayout extends StatefulWidget {
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
  State<_EmulatorStandaloneLayout> createState() =>
      _EmulatorStandaloneLayoutState();
}

class _EmulatorStandaloneLayoutState extends State<_EmulatorStandaloneLayout> {
  EmulatorPlatform _selectedPlatform = EmulatorPlatform.android;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final search = SizedBox(
          width: compact ? 180 : 220,
          child: TextField(
            controller: widget.filterController,
            onChanged: (val) {
              widget.onFilterChanged(val);
              setState(() {});
            },
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(CupertinoIcons.search, size: 18),
              suffixIcon: widget.filterController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(CupertinoIcons.clear_circled, size: 16),
                      onPressed: () {
                        widget.filterController.clear();
                        widget.onFilterChanged('');
                        setState(() {});
                      },
                    )
                  : null,
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
            if (!widget.isEmbeddedTab && Platform.isMacOS)
              const DragToMoveArea(child: SizedBox(height: 30)),
            // 顶部公用标题栏：左侧为标题与副标题，右上角为共用的模拟器平台切换 Tab
            DashboardHeaderBar(
              title: context.l10n.t('emulators'),
              subtitle: context.l10n.t('emulatorsSubtitle'),
              icon: CupertinoIcons.device_desktop,
              trailing: EmulatorPlatformTabs(
                selectedPlatform: _selectedPlatform,
                onPlatformChanged: (platform) {
                  setState(() => _selectedPlatform = platform);
                },
              ),
            ),
            // 内容区域：安卓模拟器与其他两端页面保持完全一致（搜索框 + 工具栏 + 分割线 + 表格）
            Expanded(
              child: switch (_selectedPlatform) {
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
