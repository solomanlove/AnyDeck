part of '../dashboard_screen.dart';

/// 模拟器面板的头部组件，包含标题、过滤输入框以及操作工具栏。
class _EmulatorPanelHeader extends StatelessWidget {
  const _EmulatorPanelHeader({
    required this.isExpanded,
    required this.isCompact,
    required this.filterController,
    required this.filter,
    required this.onToggleExpanded,
    required this.onFilterChanged,
    required this.onClearFilter,
    required this.onStart,
    required this.onClearData,
    required this.onDelete,
    required this.onOpenFolder,
    required this.onRefresh,
    this.onPopOut,
  });

  /// 面板是否已展开
  final bool isExpanded;

  /// 是否为紧凑布局（屏幕宽度较小时使用）
  final bool isCompact;

  /// 过滤输入框的控制器
  final TextEditingController filterController;

  /// 当前过滤文本内容
  final String filter;

  /// 切换展开/折叠状态的回调
  final VoidCallback onToggleExpanded;

  /// 过滤文本变化时的回调
  final ValueChanged<String> onFilterChanged;

  /// 清除过滤文本的回调
  final VoidCallback onClearFilter;

  /// 启动模拟器的回调
  final VoidCallback? onStart;

  /// 清除模拟器数据的回调
  final VoidCallback? onClearData;

  /// 删除模拟器的回调
  final VoidCallback? onDelete;

  /// 打开 AVD 目录的回调
  final VoidCallback? onOpenFolder;

  /// 刷新模拟器列表的回调
  final VoidCallback onRefresh;

  /// 独立窗口显示的回调
  final VoidCallback? onPopOut;

  @override
  Widget build(BuildContext context) {
    // 构建标题区域，点击可折叠/展开面板
    final title = InkWell(
      onTap: onToggleExpanded,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                context.l10n.t('emulators'),
                style: Theme.of(context).textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // 折叠/展开的旋转动画箭头
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(CupertinoIcons.chevron_down),
            ),
          ],
        ),
      ),
    );

    // 构建右侧的操作工具栏
    final toolbar = _EmulatorToolbar(
      onStart: onStart,
      onClearData: onClearData,
      onDelete: onDelete,
      onOpenFolder: onOpenFolder,
      onRefresh: onRefresh,
      onPopOut: onPopOut,
    );

    // 如果面板未展开，只显示标题和工具栏
    if (!isExpanded) {
      return Row(
        children: [
          Expanded(child: title),
          toolbar,
        ],
      );
    }

    // 紧凑布局下，标题/工具栏和搜索框分两行排列
    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: title),
              toolbar,
            ],
          ),
        ],
      );
    }

    // 宽屏布局下，标题、搜索框、工具栏单行横向排列
    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 8),
        toolbar,
      ],
    );
  }
}

/// 主操作直接显示文字，清除数据/删除收进更多菜单，避免图标歧义。
class _EmulatorToolbar extends StatelessWidget {
  const _EmulatorToolbar({
    required this.onStart,
    required this.onClearData,
    required this.onDelete,
    required this.onOpenFolder,
    required this.onRefresh,
    this.onPopOut,
    this.onColdBoot,
    this.onReconnect,
    this.onStop,
  });

  final VoidCallback? onStart;
  final VoidCallback? onClearData;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenFolder;
  final VoidCallback onRefresh;
  final VoidCallback? onPopOut;
  final VoidCallback? onColdBoot;
  final VoidCallback? onReconnect;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final actions = <(String, IconData, VoidCallback?)>[
      ('emulatorColdBoot', CupertinoIcons.arrow_clockwise, onColdBoot),
      ('openAvdFolder', CupertinoIcons.folder_open, onOpenFolder),
      ('clearEmulatorData', CupertinoIcons.arrow_counterclockwise, onClearData),
      ('deleteEmulator', CupertinoIcons.trash, onDelete),
      if (onPopOut != null) ('emulatorPopOut', Icons.open_in_new, onPopOut),
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      FilledButton.tonalIcon(
        onPressed: onStart,
        icon: const Icon(CupertinoIcons.play, size: 18),
        label: Text(context.l10n.t('launch')),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: onReconnect,
        icon: const Icon(CupertinoIcons.link, size: 18),
        label: Text(context.l10n.t('emulatorReconnect')),
      ),
      IconButton(
        tooltip: context.l10n.t('emulatorStop'),
        onPressed: onStop,
        icon: const Icon(CupertinoIcons.stop_circle, size: 22),
      ),
      IconButton(
        tooltip: context.l10n.t('refresh'),
        onPressed: onRefresh,
        icon: const Icon(CupertinoIcons.refresh, size: 22),
      ),
      PopupMenuButton<int>(
        tooltip: context.l10n.t('emulatorMore'),
        icon: const Icon(CupertinoIcons.ellipsis, size: 22),
        onSelected: (index) => actions[index].$3?.call(),
        itemBuilder: (context) => [
          for (var i = 0; i < actions.length; i++)
            PopupMenuItem(
              value: i,
              enabled: actions[i].$3 != null,
              child: Row(children: [
                Icon(actions[i].$2, size: 18),
                const SizedBox(width: 12),
                Text(context.l10n.t(actions[i].$1)),
              ]),
            ),
        ],
      ),
    ]);
  }
}
