part of '../dashboard_screen.dart';

/// 模拟器列表面板组件。
/// 用于管理和启动 Android 模拟器，支持以普通卡片组件嵌入主界面，或以独立子窗口形式运行。
class EmulatorListPanel extends ConsumerStatefulWidget {
  const EmulatorListPanel({super.key, this.isStandalone = false});

  /// 是否作为独立窗口运行
  final bool isStandalone;

  /// 打开模拟器管理器的独立窗口。
  static Future<void> openStandaloneWindow(BuildContext context) async {
    final title = context.l10n.t('emulators');
    try {
      // 创建一个新的类型为 'emulator_manager' 的子窗口
      final window = await DesktopMultiWindow.createWindow(jsonEncode({
        'type': 'emulator_manager',
      }));
      // 设置窗口默认大小和位置
      await window.setFrame(const Offset(100, 100) & const Size(900, 600));
      await window.center();
      await window.setTitle(title);
      await window.show();
    } catch (e) {
      debugPrint('Failed to open multi-window: $e');
    }
  }

  @override
  ConsumerState<EmulatorListPanel> createState() => EmulatorListPanelState();
}

class EmulatorListPanelState extends ConsumerState<EmulatorListPanel> {
  /// 用于搜索过滤模拟器列表的输入框控制器
  final TextEditingController _filterController = TextEditingController();
  /// 当前过滤关键字
  String _filter = '';
  /// 当前排序列，默认按名称 ('name') 排序
  String _sortColumn = 'name';
  /// 是否升序排列
  bool _sortAscending = true;
  /// 当前选中的模拟器的 AVD 名称
  String? _selectedName;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  /// 切换指定列的排序状态（升序、降序或切换排序列）
  void _toggleSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  /// 获取对应排序方向的图标
  Widget _getSortIcon(String column) {
    if (_sortColumn != column) {
      return const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Icon(CupertinoIcons.chevron_up_chevron_down, size: 14, color: Colors.grey),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        _sortAscending ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
        size: 14,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 独立窗口默认展开，主界面中则根据用户的折叠状态决定
    final isExpanded = widget.isStandalone ? true : ref.watch(_emulatorListExpandedProvider);
    // 监听模拟器列表异步状态
    final emulatorsAsync = ref.watch(emulatorListProvider);
    // 监听正在运行的模拟器与设备的映射状态
    final runningEmulatorsAsync = ref.watch(runningEmulatorsProvider);
    // 监听正在启动中的模拟器集合
    final startingEmulators = ref.watch(startingEmulatorsProvider);

    final emulators = emulatorsAsync.value ?? [];
    final runningMap = runningEmulatorsAsync.value ?? {};
    // 构建并排序过滤后的列表项
    final items = _buildItems(emulators, runningMap, startingEmulators);
    // 获取当前选中的列表项
    final selectedItem = _selectedItem(items);

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.hasBoundedHeight;
        final isCompact = constraints.maxWidth < 760;

        Widget contentWidget;
        if (emulatorsAsync.hasError) {
          // 加载出错时的提示界面
          contentWidget = Center(
            child: _PanelMessage(
              icon: CupertinoIcons.exclamationmark_circle,
              title: context.l10n.t('noEmulators'),
              subtitle: emulatorsAsync.error.toString(),
            ),
          );
        } else if (emulatorsAsync.isLoading && emulators.isEmpty) {
          // 正在扫描/加载中的界面
          contentWidget = Center(
            child: _PanelMessage(
              icon: CupertinoIcons.arrow_2_circlepath,
              title: context.l10n.t('scanningEmulators'),
              animateIcon: true,
            ),
          );
        } else if (items.isEmpty) {
          // 列表为空时的提示界面
          contentWidget = Center(
            child: _PanelMessage(
              icon: CupertinoIcons.device_desktop,
              title: context.l10n.t('noEmulators'),
              subtitle: _filter.trim().isEmpty
                  ? context.l10n.t('createEmulatorHint')
                  : null,
            ),
          );
        } else {
          // 展示数据表格
          contentWidget = _EmulatorTable(
            items: items,
            selectedName: _selectedName,
            onSort: _toggleSort,
            sortIconBuilder: _getSortIcon,
            onSelected: (name) {
              setState(() => _selectedName = name);
            },
            onDoubleTap: (name) {
              setState(() => _selectedName = name);
              final item = items.firstWhere((e) => e.emulator.name == name);
              showDialog<void>(
                context: context,
                builder: (context) => EmulatorFullConfigDialog(
                  emulatorName: item.emulator.displayName,
                  config: item.emulator.config,
                ),
              );
            },
          );
        }

        final layoutWidget = contentWidget;

        // 如果是独立窗口模式，使用定制的无 Card 边框布局
        if (widget.isStandalone) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 56,
                padding: EdgeInsets.only(
                  left: Platform.isMacOS ? 80 : 16,
                  right: 16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      context.l10n.t('emulators'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 240,
                          child: _EmulatorFilterField(
                            controller: _filterController,
                            filter: _filter,
                            onChanged: (value) => setState(() => _filter = value),
                            onClear: () {
                              _filterController.clear();
                              setState(() => _filter = '');
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    _EmulatorToolbar(
                      onStart: selectedItem != null && selectedItem.canStart
                          ? () => _startEmulator(context, selectedItem.emulator.name)
                          : null,
                      onClearData: selectedItem != null && selectedItem.canClearData
                          ? () => _clearEmulatorData(context, selectedItem.emulator)
                          : null,
                      onDelete: selectedItem != null && selectedItem.canDelete
                          ? () => _deleteEmulator(context, selectedItem.emulator)
                          : null,
                      onOpenFolder: selectedItem != null
                          ? () => _openAvdFolder(context, selectedItem.emulator)
                          : null,
                      onRefresh: _refreshEmulators,
                      onPopOut: null,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: layoutWidget,
                ),
              ),
            ],
          );
        }

        // 主界面中嵌入的卡片布局
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EmulatorPanelHeader(
                    isExpanded: isExpanded,
                    isCompact: isCompact,
                    filterController: _filterController,
                    filter: _filter,
                    onToggleExpanded: () {
                      ref.read(_emulatorListExpandedProvider.notifier).toggle();
                    },
                    onFilterChanged: (value) => setState(() => _filter = value),
                    onClearFilter: () {
                      _filterController.clear();
                      setState(() => _filter = '');
                    },
                    onStart: selectedItem != null && selectedItem.canStart
                        ? () => _startEmulator(
                            context,
                            selectedItem.emulator.name,
                          )
                        : null,
                    onClearData:
                        selectedItem != null && selectedItem.canClearData
                        ? () =>
                              _clearEmulatorData(context, selectedItem.emulator)
                        : null,
                    onDelete: selectedItem != null && selectedItem.canDelete
                        ? () => _deleteEmulator(context, selectedItem.emulator)
                        : null,
                    onOpenFolder: selectedItem != null
                        ? () => _openAvdFolder(context, selectedItem.emulator)
                        : null,
                    onRefresh: _refreshEmulators,
                    onPopOut: _popOutWindow,
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 12),
                    if (hasBoundedHeight)
                      Expanded(child: layoutWidget)
                    else
                      SizedBox(
                        height: 360,
                        child: layoutWidget,
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 过滤、排序并组装模拟器列表数据项
  List<_EmulatorItem> _buildItems(
    List<AndroidEmulator> emulators,
    Map<String, String> runningMap,
    Set<String> startingEmulators,
  ) {
    final query = _filter.trim().toLowerCase();
    final items = emulators
        .where((emulator) {
          if (query.isEmpty) {
            return true;
          }
          return emulator.searchableText.contains(query);
        })
        .map((emulator) {
          final isStarting = startingEmulators.contains(emulator.name);
          final runningDeviceId = runningMap[emulator.name];
          final isRunning = runningDeviceId != null;

          String status = 'stopped';
          if (isRunning) status = 'running';
          if (isStarting) status = 'starting';

          return _EmulatorItem(
            emulator: emulator,
            status: status,
            deviceId: runningDeviceId,
          );
        })
        .toList();

    // 默认排在前面的策略：非停止状态 (running/starting) 排在停止状态 (stopped) 前面
    items.sort((a, b) {
      final aActive = a.status != 'stopped';
      final bActive = b.status != 'stopped';
      if (aActive && !bActive) return -1;
      if (!aActive && bActive) return 1;

      // 按选中的排序列进行具体排序
      final cmp = switch (_sortColumn) {
        'resolution' => a.emulator.resolutionLabel.compareTo(
          b.emulator.resolutionLabel,
        ),
        'sdk' => a.emulator.sdkVersionLabel.compareTo(
          b.emulator.sdkVersionLabel,
        ),
        'abi' => a.emulator.abiLabel.compareTo(b.emulator.abiLabel),
        'memory' => a.emulator.memoryLabel.compareTo(b.emulator.memoryLabel),
        'storage' => a.emulator.storageLabel.compareTo(b.emulator.storageLabel),
        _ => a.emulator.displayName.compareTo(b.emulator.displayName),
      };
      return _sortAscending ? cmp : -cmp;
    });

    return items;
  }

  /// 获取当前选中的 _EmulatorItem 项
  _EmulatorItem? _selectedItem(List<_EmulatorItem> items) {
    final selectedName = _selectedName;
    if (selectedName == null) {
      return null;
    }
    for (final item in items) {
      if (item.emulator.name == selectedName) {
        return item;
      }
    }
    return null;
  }

  /// 刷新模拟器数据
  void _refreshEmulators() {
    ref.invalidate(emulatorListProvider);
    ref.invalidate(runningEmulatorsProvider);
  }

  /// 弹出独立窗口展示列表，同时折叠主界面的面板
  Future<void> _popOutWindow() async {
    await EmulatorListPanel.openStandaloneWindow(context);
    if (ref.read(_emulatorListExpandedProvider)) {
      ref.read(_emulatorListExpandedProvider.notifier).toggle();
    }
  }

  /// 异步执行启动模拟器操作
  Future<void> _startEmulator(BuildContext context, String avdName) async {
    ref.read(startingEmulatorsProvider.notifier).start(avdName);

    final success = await ref
        .read(emulatorServiceProvider)
        .startEmulator(avdName);
    if (!context.mounted) return;

    if (success) {
      _showSnack(context, context.l10n.t('startSuccess'));
      ref.invalidate(runningEmulatorsProvider);
    } else {
      ref.read(startingEmulatorsProvider.notifier).stopStarting(avdName);
      _showSnack(context, context.l10n.t('startFailed'), isError: true);
    }
  }

  /// 清除指定模拟器的用户数据
  Future<void> _clearEmulatorData(
    BuildContext context,
    AndroidEmulator emulator,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.t('confirm')),
          content: Text(
            context.l10n
                .t('clearEmulatorDataConfirm')
                .replaceAll('{emulator}', emulator.displayName),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.t('confirm')),
            ),
          ],
        );
      },
    );

    if (confirm != true || !context.mounted) return;

    final success = await ref
        .read(emulatorServiceProvider)
        .clearEmulatorData(emulator);
    if (!context.mounted) return;

    if (success) {
      _showSnack(context, context.l10n.t('clearEmulatorDataSuccess'));
      ref.invalidate(emulatorListProvider);
    } else {
      _showSnack(
        context,
        context.l10n.t('clearEmulatorDataFailed'),
        isError: true,
      );
    }
  }

  /// 异步执行删除模拟器操作
  Future<void> _deleteEmulator(
    BuildContext context,
    AndroidEmulator emulator,
  ) async {
    final confirm = await _confirm(
      context,
      context.l10n
          .t('deleteEmulatorConfirm')
          .replaceAll('{emulator}', emulator.displayName),
    );

    if (!confirm || !context.mounted) return;

    final success = await ref
        .read(emulatorServiceProvider)
        .deleteEmulator(emulator);
    if (!context.mounted) return;

    if (success) {
      setState(() => _selectedName = null);
      _showSnack(context, context.l10n.t('deleteEmulatorSuccess'));
      ref.invalidate(emulatorListProvider);
      ref.invalidate(runningEmulatorsProvider);
    } else {
      _showSnack(
        context,
        context.l10n.t('deleteEmulatorFailed'),
        isError: true,
      );
    }
  }

  /// 打开模拟器的 AVD 所在本地文件夹
  Future<void> _openAvdFolder(
    BuildContext context,
    AndroidEmulator emulator,
  ) async {
    final success = await ref
        .read(emulatorServiceProvider)
        .openAvdDirectory(emulator);
    if (!context.mounted) return;

    if (!success) {
      _showSnack(context, context.l10n.t('openAvdFolderFailed'), isError: true);
    }
  }
}

/// 模拟器项数据包装类，合并模拟器配置和当前状态。
class _EmulatorItem {
  const _EmulatorItem({
    required this.emulator,
    required this.status,
    this.deviceId,
  });

  /// 模拟器配置属性
  final AndroidEmulator emulator;
  /// 模拟器运行状态 ('running', 'starting', 'stopped')
  final String status;
  /// 如果运行中，对应的 ADB 设备 ID
  final String? deviceId;

  /// 能否启动（仅 stopped 状态可启动）
  bool get canStart => status == 'stopped';

  /// 能否清除数据（仅 stopped 状态可清除数据）
  bool get canClearData => status == 'stopped';

  /// 能否被删除（仅 stopped 状态可删除）
  bool get canDelete => status == 'stopped';
}
