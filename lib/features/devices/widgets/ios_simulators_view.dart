import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widget/app_toast.dart';
import '../../../core/emulator/ios/ios_simulator.dart';
import '../../../core/emulator/ios/ios_simulator_providers.dart';

/// iOS Xcode 模拟器独立管理视图。
///
/// 具备独立的操作工具栏、搜索过滤、数据表格以及启动/关闭/抹掉数据操作能力。
class IosSimulatorsView extends ConsumerStatefulWidget {
  const IosSimulatorsView({super.key});

  @override
  ConsumerState<IosSimulatorsView> createState() => _IosSimulatorsViewState();
}

class _IosSimulatorsViewState extends ConsumerState<IosSimulatorsView> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';
  String? _selectedUdid;
  bool _isActionBusy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final simulatorsAsync = ref.watch(iosSimulatorsProvider);

    final allItems = simulatorsAsync.value ?? [];
    final filtered = allItems.where((sim) {
      if (_filter.isEmpty) return true;
      final q = _filter.toLowerCase();
      return sim.name.toLowerCase().contains(q) ||
          sim.runtime.toLowerCase().contains(q) ||
          sim.udid.toLowerCase().contains(q);
    }).toList();

    final selectedSim = allItems.cast<IosSimulator?>().firstWhere(
          (s) => s?.udid == _selectedUdid,
          orElse: () => null,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;

        final searchField = SizedBox(
          width: compact ? 180 : 220,
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _filter = val.trim()),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(CupertinoIcons.search, size: 18),
              suffixIcon: _filter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(CupertinoIcons.clear_circled, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _filter = '');
                      },
                    )
                  : null,
              hintText: '搜索 iOS 模拟器...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        );

        final toolbar = _buildToolbar(context, selectedSim);

        Widget content;
        if (simulatorsAsync.isLoading && allItems.isEmpty) {
          content = const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 12),
                Text('正在扫描 Xcode 模拟器...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        } else if (filtered.isEmpty) {
          content = Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.apple, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text(
                  '未发现 iOS 模拟器',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  _filter.isNotEmpty
                      ? '没有匹配 "$_filter" 的模拟器'
                      : '请在 Xcode 的 Window -> Devices and Simulators 中创建或安装模拟器。',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          );
        } else {
          content = _buildTable(context, filtered, isDark);
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                children: [
                  searchField,
                  const Spacer(),
                  if (!compact) toolbar,
                ],
              ),
            ),
            if (compact)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: toolbar,
              ),
            const Divider(height: 1),
            Expanded(child: content),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context, IosSimulator? selected) {
    final hasSelection = selected != null;
    final isBooted = selected?.isBooted ?? false;

    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          icon: const Icon(CupertinoIcons.play_arrow, size: 16),
          label: const Text('启动'),
          onPressed: hasSelection && !isBooted && !_isActionBusy
              ? () => _bootSimulator(selected)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF09C47C),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(CupertinoIcons.stop, size: 16),
          label: const Text('关闭'),
          onPressed: hasSelection && isBooted && !_isActionBusy
              ? () => _shutdownSimulator(selected)
              : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(CupertinoIcons.delete, size: 16),
          label: const Text('抹掉数据'),
          onPressed: hasSelection && !isBooted && !_isActionBusy
              ? () => _eraseSimulator(selected)
              : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
        IconButton(
          tooltip: '打开系统 Simulator.app',
          icon: const Icon(Icons.open_in_new, size: 20),
          onPressed: () => ref.read(iosSimulatorServiceProvider).openSimulatorApp(),
        ),
        IconButton(
          tooltip: '刷新列表',
          icon: const Icon(CupertinoIcons.refresh, size: 20),
          onPressed: () => ref.invalidate(iosSimulatorsProvider),
        ),
      ],
    );
  }

  Widget _buildTable(BuildContext context, List<IosSimulator> list, bool isDark) {
    return ListView.builder(
      itemCount: list.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildTableHeader(context, isDark);
        }
        final item = list[index - 1];
        final isSelected = item.udid == _selectedUdid;

        return InkWell(
          onTap: () => setState(() => _selectedUdid = item.udid),
          onDoubleTap: () => _bootSimulator(item),
          child: Container(
            color: isSelected
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE8F4EC))
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                // 状态指示
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.isBooted
                        ? const Color(0xFF09C47C)
                        : Colors.grey.shade400,
                  ),
                ),
                const SizedBox(width: 12),
                // 模拟器名称
                Expanded(
                  flex: 3,
                  child: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 运行时系统
                Expanded(
                  flex: 2,
                  child: Text(
                    item.runtime,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 状态文本
                Expanded(
                  flex: 1,
                  child: Text(
                    item.isBooted ? '已运行' : '已关闭',
                    style: TextStyle(
                      fontSize: 12,
                      color: item.isBooted
                          ? const Color(0xFF09C47C)
                          : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                // 存储占用
                Expanded(
                  flex: 1,
                  child: Text(
                    item.displayDataSize,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                // UDID（点击可复制）
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.udid,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                        tooltip: '复制 UDID',
                        splashRadius: 16,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: item.udid));
                          AppToast.show(context, 'UDID 已复制到剪贴板');
                        },
                      ),
                    ],
                  ),
                ),
                // 操作
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!item.isBooted)
                      IconButton(
                        icon: const Icon(CupertinoIcons.play_circle,
                            color: Color(0xFF09C47C), size: 20),
                        tooltip: '启动',
                        onPressed: () => _bootSimulator(item),
                      )
                    else
                      IconButton(
                        icon: const Icon(CupertinoIcons.stop_circle,
                            color: Colors.orange, size: 20),
                        tooltip: '关闭',
                        onPressed: () => _shutdownSimulator(item),
                      ),
                    if (item.dataPath != null)
                      IconButton(
                        icon: const Icon(CupertinoIcons.folder, size: 20),
                        tooltip: '打开数据沙盒目录',
                        onPressed: () => ref
                            .read(iosSimulatorServiceProvider)
                            .openDataFolder(item.dataPath!),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader(BuildContext context, bool isDark) {
    const headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: Colors.grey,
    );

    return Container(
      color: isDark
          ? Colors.white.withValues(alpha: 0.03)
          : Colors.black.withValues(alpha: 0.02),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: const Row(
        children: [
          SizedBox(width: 20),
          Expanded(flex: 3, child: Text('模拟器名称', style: headerStyle)),
          Expanded(flex: 2, child: Text('运行时系统', style: headerStyle)),
          Expanded(flex: 1, child: Text('状态', style: headerStyle)),
          Expanded(flex: 1, child: Text('存储占用', style: headerStyle)),
          Expanded(flex: 3, child: Text('UDID', style: headerStyle)),
          SizedBox(width: 80, child: Text('操作', style: headerStyle)),
        ],
      ),
    );
  }

  Future<void> _bootSimulator(IosSimulator sim) async {
    setState(() => _isActionBusy = true);
    AppToast.show(context, '正在启动 ${sim.name}...');
    final ok = await ref.read(iosSimulatorServiceProvider).bootSimulator(sim.udid);
    if (mounted) {
      setState(() => _isActionBusy = false);
      if (ok) {
        AppToast.show(context, '${sim.name} 启动成功');
        ref.invalidate(iosSimulatorsProvider);
      } else {
        AppToast.show(context, '${sim.name} 启动失败', isError: true);
      }
    }
  }

  Future<void> _shutdownSimulator(IosSimulator sim) async {
    setState(() => _isActionBusy = true);
    final ok = await ref.read(iosSimulatorServiceProvider).shutdownSimulator(sim.udid);
    if (mounted) {
      setState(() => _isActionBusy = false);
      if (ok) {
        AppToast.show(context, '${sim.name} 已关闭');
        ref.invalidate(iosSimulatorsProvider);
      } else {
        AppToast.show(context, '关闭 ${sim.name} 失败', isError: true);
      }
    }
  }

  Future<void> _eraseSimulator(IosSimulator sim) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('抹掉模拟器内容和设置'),
        content: Text('确定要抹掉 "${sim.name}" 的所有用户数据与设置吗？该操作不可逆。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('抹掉'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isActionBusy = true);
    final ok = await ref.read(iosSimulatorServiceProvider).eraseSimulator(sim.udid);
    if (mounted) {
      setState(() => _isActionBusy = false);
      if (ok) {
        AppToast.show(context, '${sim.name} 数据已抹掉');
        ref.invalidate(iosSimulatorsProvider);
      } else {
        AppToast.show(context, '抹掉 ${sim.name} 数据失败', isError: true);
      }
    }
  }
}
