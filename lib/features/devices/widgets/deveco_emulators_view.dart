import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widget/app_toast.dart';
import '../../../core/emulator/harmony/deveco_emulator.dart';
import '../../../core/emulator/harmony/deveco_emulator_providers.dart';

/// 华为 HarmonyOS DevEco 模拟器独立管理视图。
///
/// 具备 DevEco 专属操作工具栏、搜索过滤、模拟器列表以及唤起 DevEco Studio 与目录跳转能力。
class DevecoEmulatorsView extends ConsumerStatefulWidget {
  const DevecoEmulatorsView({super.key});

  @override
  ConsumerState<DevecoEmulatorsView> createState() =>
      _DevecoEmulatorsViewState();
}

class _DevecoEmulatorsViewState extends ConsumerState<DevecoEmulatorsView> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';
  String? _selectedName;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emulatorsAsync = ref.watch(devecoEmulatorsProvider);

    final allItems = emulatorsAsync.value ?? [];
    final filtered = allItems.where((emu) {
      if (_filter.isEmpty) return true;
      final q = _filter.toLowerCase();
      return emu.name.toLowerCase().contains(q) ||
          emu.apiVersion.toLowerCase().contains(q);
    }).toList();

    final selectedEmu = allItems.cast<DevEcoEmulator?>().firstWhere(
          (e) => e?.name == _selectedName,
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
              hintText: '搜索 DevEco 模拟器...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        );

        final toolbar = _buildToolbar(context, selectedEmu);

        Widget content;
        if (emulatorsAsync.isLoading && allItems.isEmpty) {
          content = const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 12),
                Text('正在扫描 DevEco 模拟器...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        } else if (filtered.isEmpty) {
          content = Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.devices, size: 52, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    '未发现 DevEco 本地模拟器',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _filter.isNotEmpty
                        ? '没有匹配 "$_filter" 的模拟器'
                        : '请在 DevEco Studio 中通过 "Tools" -> "Device Manager" 创建或管理 HarmonyOS 模拟器。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.launch, size: 16),
                    label: const Text('打开 DevEco Studio'),
                    onPressed: _openDevEcoStudio,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF09C47C),
                    ),
                  ),
                ],
              ),
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

  Widget _buildToolbar(BuildContext context, DevEcoEmulator? selected) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          icon: const Icon(CupertinoIcons.play_arrow, size: 16),
          label: const Text('启动'),
          onPressed: selected != null && !selected.isRunning
              ? () {
                  AppToast.show(context, '请在 DevEco Studio 中启动或管理该模拟器');
                }
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF09C47C),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(CupertinoIcons.stop, size: 16),
          label: const Text('停止'),
          onPressed: selected != null && selected.isRunning
              ? () {
                  AppToast.show(context, '正在停止模拟器...');
                }
              : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
        if (selected?.configPath != null)
          OutlinedButton.icon(
            icon: const Icon(CupertinoIcons.folder, size: 16),
            label: const Text('配置目录'),
            onPressed: () => ref
                .read(devecoEmulatorServiceProvider)
                .openFolder(selected!.configPath!),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        IconButton(
          tooltip: '打开 DevEco Studio',
          icon: const Icon(Icons.open_in_new, size: 20),
          onPressed: _openDevEcoStudio,
        ),
        IconButton(
          tooltip: '刷新列表',
          icon: const Icon(CupertinoIcons.refresh, size: 20),
          onPressed: () => ref.invalidate(devecoEmulatorsProvider),
        ),
      ],
    );
  }

  Widget _buildTable(BuildContext context, List<DevEcoEmulator> list, bool isDark) {
    return ListView.builder(
      itemCount: list.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildTableHeader(context, isDark);
        }
        final item = list[index - 1];
        final isSelected = item.name == _selectedName;

        return InkWell(
          onTap: () => setState(() => _selectedName = item.name),
          child: Container(
            color: isSelected
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE8F4EC))
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.isRunning
                        ? const Color(0xFF09C47C)
                        : Colors.grey.shade400,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    item.apiVersion,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    item.deviceType,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    item.isRunning ? '已运行' : '已停止',
                    style: TextStyle(
                      fontSize: 12,
                      color: item.isRunning
                          ? const Color(0xFF09C47C)
                          : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (item.configPath != null)
                  IconButton(
                    icon: const Icon(CupertinoIcons.folder, size: 20),
                    tooltip: '打开配置目录',
                    onPressed: () => ref
                        .read(devecoEmulatorServiceProvider)
                        .openFolder(item.configPath!),
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
          Expanded(flex: 2, child: Text('系统 / API 版本', style: headerStyle)),
          Expanded(flex: 2, child: Text('设备类型', style: headerStyle)),
          Expanded(flex: 1, child: Text('状态', style: headerStyle)),
          SizedBox(width: 48, child: Text('操作', style: headerStyle)),
        ],
      ),
    );
  }

  Future<void> _openDevEcoStudio() async {
    final ok = await ref.read(devecoEmulatorServiceProvider).openDevEcoStudio();
    if (!mounted) return;
    if (!ok) {
      AppToast.show(context, '未找到 DevEco Studio 应用，请确认是否已安装。', isError: true);
    }
  }
}
