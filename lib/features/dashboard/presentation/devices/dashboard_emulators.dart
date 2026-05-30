part of '../dashboard_screen.dart';

class _EmulatorListPanel extends ConsumerStatefulWidget {
  const _EmulatorListPanel();

  @override
  ConsumerState<_EmulatorListPanel> createState() => _EmulatorListPanelState();
}

class _EmulatorListPanelState extends ConsumerState<_EmulatorListPanel> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  String _sortColumn = 'name';
  bool _sortAscending = true;
  String? _selectedName;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

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
    final isExpanded = ref.watch(_emulatorListExpandedProvider);
    final emulatorsAsync = ref.watch(emulatorListProvider);
    final runningEmulatorsAsync = ref.watch(runningEmulatorsProvider);
    final startingEmulators = ref.watch(startingEmulatorsProvider);

    final emulators = emulatorsAsync.value ?? [];
    final runningMap = runningEmulatorsAsync.value ?? {};
    final items = _buildItems(emulators, runningMap, startingEmulators);
    final selectedItem = _selectedItem(items);

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.hasBoundedHeight;
        final isCompact = constraints.maxWidth < 760;

        Widget contentWidget;
        if (emulatorsAsync.hasError) {
          contentWidget = Center(
            child: _PanelMessage(
              icon: CupertinoIcons.exclamationmark_circle,
              title: context.l10n.t('noEmulators'),
              subtitle: emulatorsAsync.error.toString(),
            ),
          );
        } else if (emulatorsAsync.isLoading && emulators.isEmpty) {
          contentWidget = Center(
            child: _PanelMessage(
              icon: CupertinoIcons.arrow_2_circlepath,
              title: context.l10n.t('scanningEmulators'),
            ),
          );
        } else if (items.isEmpty) {
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
          contentWidget = _EmulatorTable(
            items: items,
            selectedName: _selectedName,
            onSort: _toggleSort,
            sortIconBuilder: _getSortIcon,
            onSelected: (name) => setState(() => _selectedName = name),
          );
        }

        Widget layoutWidget;
        if (selectedItem != null) {
          if (isCompact) {
            layoutWidget = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 4, child: contentWidget),
                const SizedBox(height: 12),
                Expanded(
                  flex: 5,
                  child: _EmulatorDetailsPanel(
                    item: selectedItem,
                    onClose: () => setState(() => _selectedName = null),
                  ),
                ),
              ],
            );
          } else {
            layoutWidget = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: contentWidget),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _EmulatorDetailsPanel(
                    item: selectedItem,
                    onClose: () => setState(() => _selectedName = null),
                  ),
                ),
              ],
            );
          }
        } else {
          layoutWidget = contentWidget;
        }

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
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 12),
                    if (hasBoundedHeight)
                      Expanded(child: layoutWidget)
                    else
                      SizedBox(
                        height: selectedItem != null ? (isCompact ? 480 : 360) : 360,
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

    items.sort((a, b) {
      final aActive = a.status != 'stopped';
      final bActive = b.status != 'stopped';
      if (aActive && !bActive) return -1;
      if (!aActive && bActive) return 1;

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

  void _refreshEmulators() {
    ref.invalidate(emulatorListProvider);
    ref.invalidate(runningEmulatorsProvider);
  }

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
  });

  final bool isExpanded;
  final bool isCompact;
  final TextEditingController filterController;
  final String filter;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onClearFilter;
  final VoidCallback? onStart;
  final VoidCallback? onClearData;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenFolder;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
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
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(CupertinoIcons.chevron_down),
            ),
          ],
        ),
      ),
    );

    final toolbar = _EmulatorToolbar(
      onStart: onStart,
      onClearData: onClearData,
      onDelete: onDelete,
      onOpenFolder: onOpenFolder,
      onRefresh: onRefresh,
    );

    if (!isExpanded) {
      return Row(
        children: [
          Expanded(child: title),
          toolbar,
        ],
      );
    }

    final filterField = _EmulatorFilterField(
      controller: filterController,
      filter: filter,
      onChanged: onFilterChanged,
      onClear: onClearFilter,
    );

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

class _EmulatorFilterField extends StatelessWidget {
  const _EmulatorFilterField({
    required this.controller,
    required this.filter,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String filter;
  final ValueChanged<String> onChanged;
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
              ? IconButton(icon: const Icon(CupertinoIcons.clear), onPressed: onClear)
              : null,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _EmulatorToolbar extends StatelessWidget {
  const _EmulatorToolbar({
    required this.onStart,
    required this.onClearData,
    required this.onDelete,
    required this.onOpenFolder,
    required this.onRefresh,
  });

  final VoidCallback? onStart;
  final VoidCallback? onClearData;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenFolder;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.l10n.t('start'),
          icon: const Icon(CupertinoIcons.play),
          onPressed: onStart,
        ),
        IconButton(
          tooltip: context.l10n.t('clearEmulatorData'),
          icon: const Icon(CupertinoIcons.clear),
          onPressed: onClearData,
        ),
        IconButton(
          tooltip: context.l10n.t('deleteEmulator'),
          icon: const Icon(CupertinoIcons.trash),
          onPressed: onDelete,
        ),
        IconButton(
          tooltip: context.l10n.t('openAvdFolder'),
          icon: const Icon(CupertinoIcons.folder_open),
          onPressed: onOpenFolder,
        ),
        Container(
          height: 24,
          width: 1,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: Theme.of(context).dividerColor,
        ),
        IconButton(
          tooltip: context.l10n.t('refresh'),
          icon: const Icon(CupertinoIcons.refresh),
          onPressed: onRefresh,
        ),
      ],
    );
  }
}

class _EmulatorTable extends StatefulWidget {
  const _EmulatorTable({
    required this.items,
    required this.selectedName,
    required this.onSort,
    required this.sortIconBuilder,
    required this.onSelected,
  });

  final List<_EmulatorItem> items;
  final String? selectedName;
  final ValueChanged<String> onSort;
  final Widget Function(String column) sortIconBuilder;
  final ValueChanged<String> onSelected;

  @override
  State<_EmulatorTable> createState() => _EmulatorTableState();
}

class _EmulatorTableState extends State<_EmulatorTable> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _EmulatorTableWidths.adaptive(constraints.maxWidth);
        final tableWidth = max(widths.total, constraints.maxWidth);

        return Scrollbar(
          controller: _horizontalController,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalController,
            primary: false,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _EmulatorTableHeader(
                    widths: widths,
                    onSort: widget.onSort,
                    sortIconBuilder: widget.sortIconBuilder,
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalController,
                      child: ListView.builder(
                        controller: _verticalController,
                        primary: false,
                        itemCount: widget.items.length,
                        itemBuilder: (context, index) {
                          final item = widget.items[index];
                          return _EmulatorTableRow(
                            item: item,
                            widths: widths,
                            selected: item.emulator.name == widget.selectedName,
                            index: index,
                            onSelected: () =>
                                widget.onSelected(item.emulator.name),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmulatorTableWidths {
  const _EmulatorTableWidths({
    required this.name,
    required this.resolution,
    required this.sdk,
    required this.abi,
    required this.memory,
    required this.storage,
  });

  final double name;
  final double resolution;
  final double sdk;
  final double abi;
  final double memory;
  final double storage;

  double get total => name + resolution + sdk + abi + memory + storage;

  factory _EmulatorTableWidths.adaptive(double viewportWidth) {
    const fixed = 180.0 + 130.0 + 210.0 + 110.0 + 110.0;
    final name = max(280.0, viewportWidth - fixed);
    return _EmulatorTableWidths(
      name: name,
      resolution: 180,
      sdk: 130,
      abi: 210,
      memory: 110,
      storage: 110,
    );
  }
}

class _EmulatorTableHeader extends StatelessWidget {
  const _EmulatorTableHeader({
    required this.widths,
    required this.onSort,
    required this.sortIconBuilder,
  });

  final _EmulatorTableWidths widths;
  final ValueChanged<String> onSort;
  final Widget Function(String column) sortIconBuilder;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          _EmulatorHeaderCell(
            width: widths.name,
            label: context.l10n.t('emulatorNameCol'),
            style: style,
            onTap: () => onSort('name'),
            sortIcon: sortIconBuilder('name'),
          ),
          _EmulatorHeaderCell(
            width: widths.resolution,
            label: context.l10n.t('emulatorResolutionCol'),
            style: style,
            onTap: () => onSort('resolution'),
            sortIcon: sortIconBuilder('resolution'),
          ),
          _EmulatorHeaderCell(
            width: widths.sdk,
            label: context.l10n.t('emulatorSdkCol'),
            style: style,
            onTap: () => onSort('sdk'),
            sortIcon: sortIconBuilder('sdk'),
          ),
          _EmulatorHeaderCell(
            width: widths.abi,
            label: context.l10n.t('emulatorAbiCol'),
            style: style,
            onTap: () => onSort('abi'),
            sortIcon: sortIconBuilder('abi'),
          ),
          _EmulatorHeaderCell(
            width: widths.memory,
            label: context.l10n.t('emulatorMemoryCol'),
            style: style,
            onTap: () => onSort('memory'),
            sortIcon: sortIconBuilder('memory'),
          ),
          _EmulatorHeaderCell(
            width: widths.storage,
            label: context.l10n.t('emulatorStorageCol'),
            style: style,
            onTap: () => onSort('storage'),
            sortIcon: sortIconBuilder('storage'),
          ),
        ],
      ),
    );
  }
}

class _EmulatorHeaderCell extends StatelessWidget {
  const _EmulatorHeaderCell({
    required this.width,
    required this.label,
    required this.style,
    required this.onTap,
    required this.sortIcon,
  });

  final double width;
  final String label;
  final TextStyle? style;
  final VoidCallback onTap;
  final Widget sortIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              sortIcon,
            ],
          ),
        ),
      ),
    );
  }
}

class _EmulatorTableRow extends StatelessWidget {
  const _EmulatorTableRow({
    required this.item,
    required this.widths,
    required this.selected,
    required this.index,
    required this.onSelected,
  });

  final _EmulatorItem item;
  final _EmulatorTableWidths widths;
  final bool selected;
  final int index;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primaryContainer
        : index.isOdd
        ? Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
        : null;

    return InkWell(
      onTap: onSelected,
      child: Container(
        height: 40,
        color: color,
        child: Row(
          children: [
            _EmulatorCell(
              width: widths.name,
              child: Row(
                children: [
                  _EmulatorStatusDot(status: item.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _EmulatorTableText(item.emulator.displayName),
                  ),
                ],
              ),
            ),
            _EmulatorCell(
              width: widths.resolution,
              child: _EmulatorTableText(item.emulator.resolutionLabel),
            ),
            _EmulatorCell(
              width: widths.sdk,
              child: _EmulatorTableText(item.emulator.sdkVersionLabel),
            ),
            _EmulatorCell(
              width: widths.abi,
              child: _EmulatorTableText(item.emulator.abiLabel),
            ),
            _EmulatorCell(
              width: widths.memory,
              child: _EmulatorTableText(item.emulator.memoryLabel),
            ),
            _EmulatorCell(
              width: widths.storage,
              child: _EmulatorTableText(item.emulator.storageLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmulatorCell extends StatelessWidget {
  const _EmulatorCell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: child,
      ),
    );
  }
}

class _EmulatorTableText extends StatelessWidget {
  const _EmulatorTableText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: value,
      waitDuration: const Duration(milliseconds: 600),
      child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _EmulatorStatusDot extends StatelessWidget {
  const _EmulatorStatusDot({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'running' => (const Color(0xFF2E7D32), context.l10n.t('emulatorRunning')),
      'starting' => (
        const Color(0xFFE65100),
        context.l10n.t('emulatorStarting'),
      ),
      _ => (const Color(0xFF9E9E9E), context.l10n.t('emulatorStopped')),
    };

    return Tooltip(
      message: label,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _EmulatorItem {
  const _EmulatorItem({
    required this.emulator,
    required this.status,
    this.deviceId,
  });

  final AndroidEmulator emulator;
  final String status;
  final String? deviceId;

  bool get canStart => status == 'stopped';

  bool get canClearData => status == 'stopped';

  bool get canDelete => status == 'stopped';
}

/// 承载选中设备全部工具的工作区。
