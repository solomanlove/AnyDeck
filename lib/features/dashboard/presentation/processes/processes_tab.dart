import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/adb/adb_device.dart';
import '../../../../core/process/process_service.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/apps/adb_package.dart';
import '../widgets/dashboard_snack.dart';
import '../widgets/dashboard_table_header.dart';

part 'processes_tab_view.dart';
part 'processes_tab_table.dart';

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
  void didUpdateWidget(covariant ProcessesTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.device.isOnline) {
      _stopRefreshTimer();
      if (_refreshing || _selectedPid != null || _selectedProcess != null) {
        setState(() {
          _refreshing = false;
          _selectedPid = null;
          _selectedProcess = null;
        });
      }
      return;
    }

    if (!oldWidget.device.isOnline || oldWidget.device.id != widget.device.id) {
      _startRefreshTimer();
    }
  }

  @override
  void dispose() {
    _stopRefreshTimer();
    _filterController.dispose();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    if (_autoRefresh && widget.device.isOnline) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (mounted && !_refreshing && widget.device.isOnline) {
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
    if (!widget.device.isOnline) {
      if (mounted && _refreshing) {
        setState(() => _refreshing = false);
      }
      return;
    }
    if (_refreshing) return;
    if (!silent) {
      setState(() => _refreshing = true);
    }
    try {
      ref.invalidate(processesProvider(widget.device.id));
      await ref.read(processesProvider(widget.device.id).future);
    } catch (e) {
      if (mounted && !silent) {
        DashboardSnack.show(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _refreshing = false);
      }
    }
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
      DashboardSnack.show(
        context,
        '${context.l10n.t('killProcessSuccess')} (PID: ${process.pid})',
      );
      setState(() {
        _selectedPid = null;
        _selectedProcess = null;
      });
      _refreshProcesses(silent: true);
    } else {
      DashboardSnack.show(
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
          .where((p) => _isAppProcess(p.name, p.user, installedPackageNames))
          .toList();
    }

    final query = _filter.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((p) {
        final nameMatch = p.name.toLowerCase().contains(query);
        final pidMatch = p.pid.contains(query);
        final userMatch = p.user.toLowerCase().contains(query);

        // Map label match
        final basePackage = p.name.contains(':')
            ? p.name.split(':').first
            : p.name;
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
          cmp = _parseMemoryToBytes(
            a.memory,
          ).compareTo(_parseMemoryToBytes(b.memory));
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
        _sortAscending =
            false; // Default descending (e.g. highest cpu/memory first)
      }
    });
  }

  /// 供同库 extension 更新 State，避免 extension 直接调用受保护的 setState。
  void _updateState(VoidCallback fn) {
    setState(fn);
  }

  @override
  Widget build(BuildContext context) => _buildProcessesTab(context);
}
