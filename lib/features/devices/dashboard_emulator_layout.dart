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
            onChanged: widget.onFilterChanged,
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
            if (!widget.isEmbeddedTab && Platform.isMacOS)
              const DragToMoveArea(child: SizedBox(height: 30)),
            // 顶部公用标题栏：左侧为标题与副标题，右上角为共用的模拟器平台切换 Tab
            DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: 72,
                  child: Row(
                    children: [
                      Expanded(
                        child: DashboardHeaderTitle(
                          title: context.l10n.t('emulators'),
                          subtitle: context.l10n.t('emulatorsSubtitle'),
                          icon: Icons.devices_rounded,
                        ),
                      ),
                      const SizedBox(width: 16),
                      EmulatorPlatformTabs(
                        selectedPlatform: _selectedPlatform,
                        onPlatformChanged: (platform) {
                          setState(() => _selectedPlatform = platform);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            // 内容区域：安卓模拟器与其他两端页面保持完全一致（搜索框 + 工具栏 + 分割线 + 表格）
            Expanded(
              child: switch (_selectedPlatform) {
                EmulatorPlatform.android => Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
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
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
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
