import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widget/app_toast.dart';
import '../../../app/theme/app_theme.dart';
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
                    _filter.isNotEmpty ? '没有匹配 "$_filter" 的模拟器' : '请在 DevEco Studio 中通过 "Tools" -> "Device Manager" 创建或管理 HarmonyOS 模拟器。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.launch, size: 16),
                    label: const Text('打开 DevEco Studio'),
                    onPressed: _openDevEcoStudio,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.primary,
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
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
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
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
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
            backgroundColor: AppPalette.primary,
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
          return _buildTableHeader(context);
        }
        final item = list[index - 1];
        final isSelected = item.name == _selectedName;

        return InkWell(
          onTap: () => setState(() => _selectedName = item.name),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.35)
                  : index % 2 == 0
                  ? null
                  : Theme.of(
                      context,
                    ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.isRunning
                        ? AppPalette.primary
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
                      color: Theme.of(context).appColors.toolbarForeground,
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
                          ? AppPalette.primary
                          : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: item.configPath != null
                      ? IconButton(
                          icon: const Icon(CupertinoIcons.folder, size: 20),
                          tooltip: '打开配置目录',
                          onPressed: () => ref
                              .read(devecoEmulatorServiceProvider)
                              .openFolder(item.configPath!),
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          const SizedBox(width: 20),
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
