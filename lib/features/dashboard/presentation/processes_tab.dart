import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/process/process_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/apps/adb_package.dart';

/// 进程管理标签页。
class ProcessesTab extends ConsumerStatefulWidget {
  final AdbDevice device;

  const ProcessesTab({super.key, required this.device});

  @override
  ConsumerState<ProcessesTab> createState() => _ProcessesTabState();
}

class _ProcessesTabState extends ConsumerState<ProcessesTab> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  bool _onlyShowApps = true;
  String? _selectedPid;
  AdbProcess? _selectedProcess;

  String _sortColumn = 'cpu'; // 'name', 'cpu', 'time', 'memory', 'pid', 'user'
  bool _sortAscending = false;

  Timer? _refreshTimer;
  bool _autoRefresh = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _stopRefreshTimer();
    _filterController.dispose();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    if (_autoRefresh) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (mounted && !_refreshing) {
          _refreshProcesses(silent: true);
        }
      });
    }
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
  }

  void _toggleAutoRefresh(bool? value) {
    if (value == null) return;
    setState(() {
      _autoRefresh = value;
      if (_autoRefresh) {
        _startRefreshTimer();
      } else {
        _stopRefreshTimer();
      }
    });
  }

  Future<void> _refreshProcesses({bool silent = false}) async {
    if (_refreshing) return;
    if (!silent) {
      setState(() => _refreshing = true);
    }
    try {
      ref.invalidate(processesProvider(widget.device.id));
      await ref.read(processesProvider(widget.device.id).future);
    } catch (e) {
      if (mounted && !silent) {
        _showSnack(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _refreshing = false);
      }
    }
  }

  void _showSnack(BuildContext context, String message, {bool isError = false}) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final media = MediaQuery.of(context);
    final accentColor = isError
        ? Theme.of(context).colorScheme.error
        : const Color(0xff00c853);
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: const Color(0xff171a21),
      fontWeight: FontWeight.w600,
    );

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: media.padding.top + 16,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: media.size.width - 64),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xffd7dce5)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isError ? Icons.error : Icons.check_circle,
                          color: accentColor,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Flexible(child: Text(message, style: textStyle)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Timer(const Duration(seconds: 2), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  Future<void> _killProcess() async {
    final process = _selectedProcess;
    if (process == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.t('confirm')),
          content: Text(
            context.l10n
                .t('killProcessConfirm')
                .replaceAll('{name}', process.name)
                .replaceAll('{pid}', process.pid),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.t('cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.t('confirm')),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    final result = await ref
        .read(processServiceProvider)
        .killProcess(widget.device.id, process.pid);

    if (!mounted) return;

    if (result.isSuccess) {
      _showSnack(
        context,
        '${context.l10n.t('killProcessSuccess')} (PID: ${process.pid})',
      );
      setState(() {
        _selectedPid = null;
        _selectedProcess = null;
      });
      _refreshProcesses(silent: true);
    } else {
      _showSnack(
        context,
        '${context.l10n.t('killProcessFailed')}: ${result.message}',
        isError: true,
      );
    }
  }

  /// Parses memory values like "347M", "5.3G", "512K", "100" to bytes for sorting comparison.
  double _parseMemoryToBytes(String memory) {
    if (memory.isEmpty) return 0;
    final normalized = memory.toUpperCase().trim();
    final numberPart = RegExp(r'^\d+(\.\d+)?').stringMatch(normalized) ?? '';
    final value = double.tryParse(numberPart) ?? 0.0;

    if (normalized.endsWith('G')) {
      return value * 1024 * 1024 * 1024;
    } else if (normalized.endsWith('M')) {
      return value * 1024 * 1024;
    } else if (normalized.endsWith('K')) {
      return value * 1024;
    }
    return value;
  }

  /// Parses CPU percentage like "12.9" to double.
  double _parseCpuToDouble(String cpu) {
    if (cpu.isEmpty) return 0.0;
    final cleaned = cpu.replaceAll('%', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  /// Helper to check if process belongs to an app.
  bool _isAppProcess(
    String processName,
    String user,
    List<String> installedPackageNames,
  ) {
    if (user.startsWith('u0_') || user.startsWith('u1_')) {
      return true;
    }
    final basePackage = processName.contains(':')
        ? processName.split(':').first
        : processName;
    if (installedPackageNames.contains(basePackage)) {
      return true;
    }

    // Regex check for package name structure (e.g. com.example.app)
    final packageRegex = RegExp(
      r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
    );
    if (packageRegex.hasMatch(basePackage) &&
        !processName.startsWith('/') &&
        !processName.startsWith('[')) {
      final systemExclude = [
        'init',
        'toybox',
        'toolbox',
        'logd',
        'debuggerd',
        'servicemanager',
        'rild',
      ];
      if (!systemExclude.contains(basePackage)) {
        return true;
      }
    }
    return false;
  }

  List<AdbProcess> _sortAndFilterProcesses(
    List<AdbProcess> items,
    List<AdbPackage> packages,
  ) {
    final installedPackageNames = packages.map((p) => p.name).toList();

    // 1. Filter
    var filtered = items;
    if (_onlyShowApps) {
      filtered = filtered
          .where(
            (p) => _isAppProcess(p.name, p.user, installedPackageNames),
          )
          .toList();
    }

    final query = _filter.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((p) {
        final nameMatch = p.name.toLowerCase().contains(query);
        final pidMatch = p.pid.contains(query);
        final userMatch = p.user.toLowerCase().contains(query);

        // Map label match
        final basePackage = p.name.contains(':') ? p.name.split(':').first : p.name;
        final matchedPkg = packages.firstWhere(
          (pkg) => pkg.name == basePackage,
          orElse: () => AdbPackage(name: '', system: false, enabled: true),
        );
        final labelMatch =
            matchedPkg.name.isNotEmpty &&
            matchedPkg.displayName.toLowerCase().contains(query);

        return nameMatch || pidMatch || userMatch || labelMatch;
      }).toList();
    }

    // 2. Sort
    filtered.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
        case 'name':
          // Resolve labels to sort by friendly display name if available
          final baseA = a.name.contains(':') ? a.name.split(':').first : a.name;
          final baseB = b.name.contains(':') ? b.name.split(':').first : b.name;
          final pkgA = packages.firstWhere(
            (pkg) => pkg.name == baseA,
            orElse: () => AdbPackage(name: '', system: false, enabled: true),
          );
          final pkgB = packages.firstWhere(
            (pkg) => pkg.name == baseB,
            orElse: () => AdbPackage(name: '', system: false, enabled: true),
          );
          final labelA = pkgA.name.isNotEmpty ? pkgA.displayName : a.name;
          final labelB = pkgB.name.isNotEmpty ? pkgB.displayName : b.name;
          cmp = labelA.toLowerCase().compareTo(labelB.toLowerCase());
          break;
        case 'cpu':
          cmp = _parseCpuToDouble(a.cpu).compareTo(_parseCpuToDouble(b.cpu));
          break;
        case 'time':
          cmp = a.cpuTime.compareTo(b.cpuTime);
          break;
        case 'memory':
          cmp = _parseMemoryToBytes(a.memory).compareTo(_parseMemoryToBytes(b.memory));
          break;
        case 'pid':
          cmp = (int.tryParse(a.pid) ?? 0).compareTo(int.tryParse(b.pid) ?? 0);
          break;
        case 'user':
          cmp = a.user.toLowerCase().compareTo(b.user.toLowerCase());
          break;
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });

    return filtered;
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = false; // Default descending (e.g. highest cpu/memory first)
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final processesAsync = ref.watch(processesProvider(widget.device.id));
    final packagesAsync = ref.watch(packagesProvider(widget.device.id));

    // Resolve list of packages
    final List<AdbPackage> packages = packagesAsync.value ?? [];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Top Action Bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filterController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: context.l10n.t('filterPackage'),
                    suffixIcon: _filter.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _filterController.clear();
                              setState(() => _filter = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) => setState(() => _filter = value),
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _onlyShowApps,
                    onChanged: (value) =>
                        setState(() => _onlyShowApps = value ?? true),
                  ),
                  Text(context.l10n.t('onlyShowApps')),
                ],
              ),
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _autoRefresh,
                    onChanged: _toggleAutoRefresh,
                  ),
                  const Text('自动刷新 (3s)'),
                ],
              ),
              const SizedBox(width: 8),
              Container(
                height: 24,
                width: 1,
                color: Theme.of(context).dividerColor,
              ),
              const SizedBox(width: 8),
              processesAsync.when(
                data: (items) {
                  final filtered = _sortAndFilterProcesses(items, packages);
                  return Text(
                    context.l10n
                        .t('processCount')
                        .replaceAll('{count}', '${filtered.length}'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  );
                },
                loading: () => const Text('读取中...'),
                error: (_, error) => const Text('加载失败'),
              ),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: '手动刷新进程',
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: _refreshing ? null : () => _refreshProcesses(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(
                  backgroundColor: _selectedPid != null
                      ? Theme.of(context).colorScheme.errorContainer
                      : null,
                  foregroundColor: _selectedPid != null
                      ? Theme.of(context).colorScheme.onErrorContainer
                      : null,
                ),
                tooltip: '结束选中的进程',
                onPressed: _selectedPid != null ? _killProcess : null,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Process Table
          Expanded(
            child: processesAsync.when(
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在加载手机进程列表...'),
                  ],
                ),
              ),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('加载进程列表失败: $error'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _refreshProcesses(),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (items) {
                final filtered = _sortAndFilterProcesses(items, packages);

                if (filtered.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.list_alt_outlined, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('未发现匹配的运行进程'),
                      ],
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final widths = _ProcessTableWidths.adaptive(
                      viewportWidth: constraints.maxWidth,
                    );

                    return _ProcessTable(
                      deviceId: widget.device.id,
                      processes: filtered,
                      packages: packages,
                      selectedPid: _selectedPid,
                      widths: widths,
                      sortColumn: _sortColumn,
                      sortAscending: _sortAscending,
                      onSort: _onSort,
                      onSelected: (process) {
                        setState(() {
                          if (_selectedPid == process.pid) {
                            _selectedPid = null;
                            _selectedProcess = null;
                          } else {
                            _selectedPid = process.pid;
                            _selectedProcess = process;
                          }
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessTableWidths {
  final double name;
  final double cpu;
  final double time;
  final double memory;
  final double pid;
  final double user;

  const _ProcessTableWidths({
    required this.name,
    required this.cpu,
    required this.time,
    required this.memory,
    required this.pid,
    required this.user,
  });

  factory _ProcessTableWidths.adaptive({required double viewportWidth}) {
    // Distribute widths based on typical sizes
    const double minTotal = 820.0;
    if (viewportWidth > minTotal) {
      final double extra = viewportWidth - minTotal;
      return _ProcessTableWidths(
        name: 300.0 + extra * 0.7,
        cpu: 110.0,
        time: 120.0,
        memory: 100.0,
        pid: 90.0,
        user: 100.0 + extra * 0.3,
      );
    } else {
      return const _ProcessTableWidths(
        name: 300.0,
        cpu: 110.0,
        time: 120.0,
        memory: 100.0,
        pid: 90.0,
        user: 100.0,
      );
    }
  }

  double get total => name + cpu + time + memory + pid + user;
}

class _ProcessTable extends StatefulWidget {
  final String deviceId;
  final List<AdbProcess> processes;
  final List<AdbPackage> packages;
  final String? selectedPid;
  final _ProcessTableWidths widths;
  final String sortColumn;
  final bool sortAscending;
  final ValueChanged<String> onSort;
  final ValueChanged<AdbProcess> onSelected;

  const _ProcessTable({
    required this.deviceId,
    required this.processes,
    required this.packages,
    required this.selectedPid,
    required this.widths,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.onSelected,
  });

  @override
  State<_ProcessTable> createState() => _ProcessTableState();
}

class _ProcessTableState extends State<_ProcessTable> {
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
    final tableWidth = max(widget.widths.total, MediaQuery.of(context).size.width);

    return Scrollbar(
      controller: _horizontalController,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              // Header
              _buildTableHeader(context),
              // Body
              Expanded(
                child: Scrollbar(
                  controller: _verticalController,
                  child: ListView.builder(
                    controller: _verticalController,
                    itemCount: widget.processes.length,
                    itemBuilder: (context, index) {
                      final process = widget.processes[index];
                      return _buildTableRow(context, process, index);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final headerStyle = textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    Widget headerCell(String column, String label, double width) {
      final isSorted = widget.sortColumn == column;
      return InkWell(
        onTap: () => widget.onSort(column),
        child: Container(
          width: width,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: headerStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSorted) ...[
                const SizedBox(width: 4),
                Icon(
                  widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          headerCell('name', context.l10n.t('processName'), widget.widths.name),
          headerCell('cpu', context.l10n.t('cpuPercent'), widget.widths.cpu),
          headerCell('time', context.l10n.t('cpuTime'), widget.widths.time),
          headerCell('memory', context.l10n.t('memory'), widget.widths.memory),
          headerCell('pid', context.l10n.t('pid'), widget.widths.pid),
          headerCell('user', context.l10n.t('user'), widget.widths.user),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, AdbProcess process, int index) {
    final isSelected = process.pid == widget.selectedPid;
    final basePackage = process.name.contains(':') ? process.name.split(':').first : process.name;

    final matchedPackage = widget.packages.firstWhere(
      (pkg) => pkg.name == basePackage,
      orElse: () => AdbPackage(name: '', system: false, enabled: true),
    );

    // Row alternating background
    final Color? rowColor = isSelected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
        : index % 2 == 0
            ? null
            : Theme.of(context).colorScheme.surfaceContainerLowest.withValues(alpha: 0.5);

    return InkWell(
      onTap: () => widget.onSelected(process),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: rowColor,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Process Name cell
            Container(
              width: widget.widths.name,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 28,
                      height: 28,
                      color: Colors.transparent,
                      child: matchedPackage.name.isNotEmpty &&
                              matchedPackage.iconLocalPath != null &&
                              File(matchedPackage.iconLocalPath!).existsSync()
                          ? Image.file(
                              File(matchedPackage.iconLocalPath!),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(matchedPackage),
                            )
                          : _buildFallbackIcon(matchedPackage),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          matchedPackage.name.isNotEmpty
                              ? (process.name.contains(':')
                                  ? '${matchedPackage.displayName}:${process.name.split(':').sublist(1).join(':')}'
                                  : matchedPackage.displayName)
                              : process.name,
                          style: TextStyle(
                            fontWeight: matchedPackage.name.isNotEmpty
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (matchedPackage.name.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            process.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ]
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // CPU cell
            _buildTextCell(process.cpu, widget.widths.cpu),
            // CPU Time cell
            _buildTextCell(process.cpuTime, widget.widths.time),
            // Memory cell
            _buildTextCell(process.memory, widget.widths.memory),
            // PID cell
            _buildTextCell(process.pid, widget.widths.pid),
            // User cell
            _buildTextCell(process.user, widget.widths.user),
          ],
        ),
      ),
    );
  }

  Widget _buildTextCell(String text, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _buildFallbackIcon(AdbPackage package) {
    if (package.name.isEmpty) {
      return const Icon(
        Icons.android,
        color: Colors.grey,
        size: 20,
      );
    }
    final icon = package.flutter
        ? Icons.flutter_dash
        : package.system
            ? Icons.settings_applications
            : Icons.android;
    final color = package.system
        ? Colors.grey[600]
        : Colors.green[600];
    return Icon(
      icon,
      color: color,
      size: 20,
    );
  }
}
