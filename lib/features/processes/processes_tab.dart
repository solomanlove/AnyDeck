import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/adb_device.dart';
import '../../core/process/process_service.dart';
import '../../core/providers/app_providers.dart';
import '../../core/apps/adb_package.dart';
import '../widgets/dashboard_snack.dart';
import '../widgets/dashboard_table_header.dart';

part 'processes_tab_view.dart';
part 'processes_tab_table.dart';

enum _ProcessContextAction { copyName, stop }

/// 进程类型过滤选项：用户进程、系统进程、全部。
enum ProcessFilterType {
  /// 用户安装的应用及其进程。
  user,
  /// 系统级应用与系统服务进程。
  system,
  /// 全部进程。
  all,
}

class ProcessesTab extends ConsumerStatefulWidget {
  final AdbDevice device;
  final bool isVisible;

  const ProcessesTab({
    super.key,
    required this.device,
    required this.isVisible,
  });

  @override
  ConsumerState<ProcessesTab> createState() => _ProcessesTabState();
}

class _ProcessesTabState extends ConsumerState<ProcessesTab> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  ProcessFilterType _processFilterType = ProcessFilterType.user;
  bool _onlyShowApps = true;
  String? _selectedPid;

  String _sortColumn = 'cpu'; // 'name', 'cpu', 'time', 'memory', 'pid', 'user'
  bool _sortAscending = false;

  Timer? _refreshTimer;
  bool _autoRefresh = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // 仅在当前 tab 可见时启动定时器
    if (widget.isVisible) {
      _startRefreshTimer();
    }
  }

  @override
  void didUpdateWidget(covariant ProcessesTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.device.isOnline) {
      _stopRefreshTimer();
      if (_refreshing || _selectedPid != null) {
        setState(() {
          _refreshing = false;
          _selectedPid = null;
        });
      }
      return;
    }

    // 当设备切换、在线状态改变或可见性改变时，重新处理轮询状态
    if (widget.device.id != oldWidget.device.id ||
        widget.device.isOnline != oldWidget.device.isOnline ||
        widget.isVisible != oldWidget.isVisible) {
      _stopRefreshTimer();
      if (widget.device.isOnline && widget.isVisible) {
        _startRefreshTimer();
      }
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
    if (!widget.isVisible) return;
    final isOnline = ref.read(deviceOnlineProvider(widget.device.id));
    if (_autoRefresh && isOnline) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (mounted && !_refreshing) {
          final stillOnline = ref.read(deviceOnlineProvider(widget.device.id));
          if (stillOnline && widget.isVisible) {
            _refreshProcesses(silent: true);
          } else {
            _stopRefreshTimer();
          }
        }
      });
    }
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
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

  /// 右键选中目标进程，并在指针位置展示进程操作菜单。
  Future<void> _showProcessContextMenu(
    AdbProcess process,
    Offset position,
  ) async {
    setState(() => _selectedPid = process.pid);

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final result = await showMenu<_ProcessContextAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      color: Theme.of(context).colorScheme.surfaceContainer,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      items: [
        PopupMenuItem<_ProcessContextAction>(
          value: _ProcessContextAction.copyName,
          height: 38,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.doc_on_doc, size: 16),
              const SizedBox(width: 8),
              Text(context.l10n.t('copyProcessName')),
            ],
          ),
        ),
        PopupMenuItem<_ProcessContextAction>(
          value: _ProcessContextAction.stop,
          height: 38,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.stop_circle,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(context.l10n.t('stopThisProcess')),
            ],
          ),
        ),
      ],
    );

    if (result == _ProcessContextAction.copyName && mounted) {
      await Clipboard.setData(ClipboardData(text: process.name));
      if (mounted) {
        DashboardSnack.show(context, context.l10n.t('copySuccess'));
      }
    } else if (result == _ProcessContextAction.stop && mounted) {
      await _killProcess(process);
    }
  }

  Future<void> _killProcess(AdbProcess process) async {
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
        .killProcess(widget.device.id, process.pid, processName: process.name);

    if (!mounted) return;

    if (result.isSuccess) {
      DashboardSnack.show(
        context,
        '${context.l10n.t('killProcessSuccess')} (PID: ${process.pid})',
      );
      if (_selectedPid == process.pid) {
        setState(() => _selectedPid = null);
      }
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

  /// 判断进程是否属于用户安装的第三方应用进程。
  bool _isUserProcess(AdbProcess process, Map<String, AdbPackage> packageMap) {
    final basePackage = process.name.contains(':')
        ? process.name.split(':').first
        : process.name;
    final pkg = packageMap[basePackage];
    if (pkg != null) return !pkg.system;
    if (packageMap.isNotEmpty) return false;
    if (!process.user.startsWith('u0_') && !process.user.startsWith('u1_')) {
      return false;
    }
    const systemPrefixes = [
      'com.android.', 'android.', 'com.google.android.', 'com.miui.',
      'com.xiaomi.', 'com.huawei.', 'com.oppo.', 'com.vivo.', 'com.samsung.',
    ];
    final lower = basePackage.toLowerCase();
    return !systemPrefixes.any(lower.startsWith);
  }

  List<AdbProcess> _sortAndFilterProcesses(
    List<AdbProcess> items,
    List<AdbPackage> packages,
  ) {
    final installedPackageNames = packages.map((p) => p.name).toList();
    final packageMap = {for (final p in packages) p.name: p};

    // 1. Filter
    var filtered = items;

    // 按进程类别过滤（用户进程 / 系统进程 / 全部）
    switch (_processFilterType) {
      case ProcessFilterType.user:
        filtered = filtered.where((p) => _isUserProcess(p, packageMap)).toList();
        break;
      case ProcessFilterType.system:
        filtered = filtered.where((p) => !_isUserProcess(p, packageMap)).toList();
        break;
      case ProcessFilterType.all:
        break;
    }

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
  Widget build(BuildContext context) {
    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));
    if (!isOnline) {
      _stopRefreshTimer();
    }
    return _buildProcessesTab(context);
  }
}
