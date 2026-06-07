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

    // 构建过滤搜索框
    final filterField = _EmulatorFilterField(
      controller: filterController,
      filter: filter,
      onChanged: onFilterChanged,
      onClear: onClearFilter,
    );

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
          const SizedBox(height: 8),
          filterField,
        ],
      );
    }

    // 宽屏布局下，标题、搜索框、工具栏单行横向排列
    return Row(
      children: [
        Expanded(child: title),
        SizedBox(width: 240, child: filterField),
        const SizedBox(width: 8),
        toolbar,
      ],
    );
  }
}

/// 模拟器列表过滤搜索输入框。
class _EmulatorFilterField extends StatelessWidget {
  const _EmulatorFilterField({
    required this.controller,
    required this.filter,
    required this.onChanged,
    required this.onClear,
  });

  /// 输入框控制器
  final TextEditingController controller;

  /// 当前过滤文本内容
  final String filter;

  /// 文本变化时的回调
  final ValueChanged<String> onChanged;

  /// 清除文本的回调
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          prefixIcon: const Icon(CupertinoIcons.search),
          labelText: context.l10n.t('filterEmulator'),
          suffixIcon: filter.isNotEmpty
              ? IconButton(
                  icon: const Icon(CupertinoIcons.clear),
                  onPressed: onClear,
                )
              : null,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// 模拟器操作工具栏，包含启动、清除数据、删除、打开文件夹、独立窗口、刷新等按钮。
class _EmulatorToolbar extends StatelessWidget {
  const _EmulatorToolbar({
    required this.onStart,
    required this.onClearData,
    required this.onDelete,
    required this.onOpenFolder,
    required this.onRefresh,
    this.onPopOut,
  });

  /// 启动模拟器
  final VoidCallback? onStart;

  /// 清除数据
  final VoidCallback? onClearData;

  /// 删除模拟器
  final VoidCallback? onDelete;

  /// 打开 AVD 文件夹
  final VoidCallback? onOpenFolder;

  /// 刷新列表
  final VoidCallback onRefresh;

  /// 弹出独立窗口
  final VoidCallback? onPopOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 启动按钮
        IconButton(
          tooltip: context.l10n.t('launch'),
          icon: const Icon(CupertinoIcons.play),
          onPressed: onStart,
        ),
        // 清除数据按钮
        IconButton(
          tooltip: context.l10n.t('clearEmulatorData'),
          icon: const Icon(CupertinoIcons.clear),
          onPressed: onClearData,
        ),
        // 删除模拟器按钮
        IconButton(
          tooltip: context.l10n.t('deleteEmulator'),
          icon: const Icon(CupertinoIcons.trash),
          onPressed: onDelete,
        ),
        // 打开 AVD 目录按钮
        IconButton(
          tooltip: context.l10n.t('openAvdFolder'),
          icon: const Icon(CupertinoIcons.folder_open),
          onPressed: onOpenFolder,
        ),
        // 弹出窗口按钮 (如果提供了回调)
        if (onPopOut != null)
          IconButton(
            tooltip: '独立窗口显示',
            icon: const Icon(Icons.open_in_new),
            onPressed: onPopOut,
          ),
        // 分割线
        Container(
          height: 24,
          width: 1,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: Theme.of(context).dividerColor,
        ),
        // 刷新列表按钮
        IconButton(
          tooltip: context.l10n.t('refresh'),
          icon: const Icon(CupertinoIcons.refresh),
          onPressed: onRefresh,
        ),
      ],
    );
  }
}
