part of 'dashboard_screen.dart';

class _EmulatorListPanel extends ConsumerStatefulWidget {
  const _EmulatorListPanel();

  @override
  ConsumerState<_EmulatorListPanel> createState() => _EmulatorListPanelState();
}

class _EmulatorListPanelState extends ConsumerState<_EmulatorListPanel> {
  String _sortColumn = 'name';
  bool _sortAscending = true;

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
        child: Icon(Icons.unfold_more, size: 14, color: Colors.grey),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        _sortAscending ? Icons.expand_less : Icons.expand_more,
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

    // 组合数据
    final items = emulators.map((name) {
      final isStarting = startingEmulators.contains(name);
      final runningDeviceId = runningMap[name];
      final isRunning = runningDeviceId != null;

      String status = 'stopped';
      if (isRunning) status = 'running';
      if (isStarting) status = 'starting';

      return _EmulatorItem(
        name: name,
        status: status,
        deviceId: runningDeviceId,
      );
    }).toList();

    // 排序
    items.sort((a, b) {
      // 运行中和启动中的置顶
      final aActive = a.status != 'stopped';
      final bActive = b.status != 'stopped';
      if (aActive && !bActive) return -1;
      if (!aActive && bActive) return 1;

      int cmp = 0;
      if (_sortColumn == 'name') {
        cmp = a.name.compareTo(b.name);
      } else if (_sortColumn == 'status') {
        cmp = a.status.compareTo(b.status);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact = constraints.maxWidth < 600;
        final bool hasBoundedHeight = constraints.hasBoundedHeight;

        Widget contentWidget;
        if (emulatorsAsync.hasError) {
          contentWidget = Center(
            child: _PanelMessage(
              icon: Icons.error_outline,
              title: context.l10n.t('noEmulators'),
              subtitle: emulatorsAsync.error.toString(),
            ),
          );
        } else if (emulatorsAsync.isLoading && emulators.isEmpty) {
          contentWidget = Center(
            child: _PanelMessage(
              icon: Icons.sync,
              title: context.l10n.t('scanningEmulators'),
            ),
          );
        } else if (items.isEmpty) {
          contentWidget = Center(
            child: _PanelMessage(
              icon: Icons.devices_other_outlined,
              title: context.l10n.t('noEmulators'),
              subtitle: context.l10n.t('createEmulatorHint'),
            ),
          );
        } else {
          contentWidget = ListView.separated(
            shrinkWrap: !hasBoundedHeight,
            physics: hasBoundedHeight
                ? null
                : const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
            itemBuilder: (context, index) {
              final item = items[index];

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    // Emulator Name
                    Expanded(
                      flex: 5,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.tablet_android,
                            color: Color(0xFF26A69A),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.name.replaceAll('_', ' '),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Status Badge
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusBgColor(item.status),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getStatusText(context, item.status),
                            style: TextStyle(
                              color: _getStatusTextColor(item.status),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Actions
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          if (item.status == 'running')
                            IconButton(
                              icon: const Icon(
                                Icons.stop_circle_outlined,
                                color: Colors.red,
                              ),
                              tooltip: context.l10n.t('stop'),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _stopEmulator(context, item),
                            )
                          else if (item.status == 'stopped')
                            IconButton(
                              icon: const Icon(
                                Icons.play_circle_outline,
                                color: Colors.green,
                              ),
                              tooltip: context.l10n.t('start'),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () =>
                                  _startEmulator(context, item.name),
                            )
                          else
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                    if (!isCompact) ...[
                      const SizedBox(width: 10),
                      const SizedBox(width: 40),
                    ],
                  ],
                ),
              );
            },
          );
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
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            ref
                                .read(_emulatorListExpandedProvider.notifier)
                                .toggle();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  context.l10n.t('emulators'),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(width: 8),
                                AnimatedRotation(
                                  turns: isExpanded ? 0.5 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: const Icon(Icons.keyboard_arrow_down),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          ref.invalidate(emulatorListProvider);
                          ref.invalidate(runningEmulatorsProvider);
                        },
                      ),
                    ],
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 16),
                    // Table Header Row
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).dividerColor,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Name header
                          Expanded(
                            flex: 5,
                            child: InkWell(
                              onTap: () => _toggleSort('name'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      context.l10n.t('emulatorNameCol'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    _getSortIcon('name'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Status header
                          Expanded(
                            flex: 3,
                            child: InkWell(
                              onTap: () => _toggleSort('status'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      context.l10n.t('emulatorStatusCol'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    _getSortIcon('status'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Actions header
                          Expanded(
                            flex: 2,
                            child: Text(
                              context.l10n.t('emulatorActionsCol'),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (!isCompact) ...[
                            const SizedBox(width: 10),
                            const SizedBox(width: 40),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Table Body Row
                    if (hasBoundedHeight)
                      Expanded(child: contentWidget)
                    else
                      contentWidget,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getStatusBgColor(String status) {
    return switch (status) {
      'running' => const Color(0xFFE8F5E9),
      'starting' => const Color(0xFFFFF3E0),
      'stopped' => const Color(0xFFF5F5F5),
      _ => const Color(0xFFF5F5F5),
    };
  }

  Color _getStatusTextColor(String status) {
    return switch (status) {
      'running' => const Color(0xFF2E7D32),
      'starting' => const Color(0xFFE65100),
      'stopped' => const Color(0xFF9E9E9E),
      _ => const Color(0xFF9E9E9E),
    };
  }

  String _getStatusText(BuildContext context, String status) {
    return switch (status) {
      'running' => context.l10n.t('emulatorRunning'),
      'starting' => context.l10n.t('emulatorStarting'),
      'stopped' => context.l10n.t('emulatorStopped'),
      _ => status,
    };
  }

  Future<void> _startEmulator(BuildContext context, String avdName) async {
    ref.read(startingEmulatorsProvider.notifier).start(avdName);

    final success = await ref
        .read(emulatorServiceProvider)
        .startEmulator(avdName);
    if (!context.mounted) return;

    if (success) {
      _showSnack(context, context.l10n.t('startSuccess'));
    } else {
      ref.read(startingEmulatorsProvider.notifier).stopStarting(avdName);
      _showSnack(context, '启动模拟器失败', isError: true);
    }
  }

  Future<void> _stopEmulator(BuildContext context, _EmulatorItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.t('confirm')),
          content: Text(
            context.l10n
                .t('stopEmulatorConfirm')
                .replaceAll('{emulator}', item.name.replaceAll('_', ' ')),
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

    if (item.deviceId == null) {
      _showSnack(context, context.l10n.t('stopFailed'), isError: true);
      return;
    }

    final adb = ref.read(adbServiceProvider);
    final result = await adb.run(['-s', item.deviceId!, 'emu', 'kill']);
    if (!context.mounted) return;

    if (result.isSuccess) {
      _showSnack(context, context.l10n.t('stopSuccess'));
      ref.invalidate(devicesProvider);
    } else {
      _showSnack(
        context,
        '${context.l10n.t('stopFailed')}: ${result.message}',
        isError: true,
      );
    }
  }
}

class _EmulatorItem {
  const _EmulatorItem({
    required this.name,
    required this.status,
    this.deviceId,
  });

  final String name;
  final String status;
  final String? deviceId;
}

/// 承载选中设备全部工具的工作区。
