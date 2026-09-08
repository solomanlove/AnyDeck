import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/apps/adb_package.dart';
import '../controller/mirror_app_quick_actions_controller.dart';
import '../model/mirror_app_quick_actions_data.dart';
import 'mirror_app_quick_action_item.dart';

/// 弹出前台应用快捷操作对话框
void showMirrorAppQuickActionsDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String deviceId,
  required AdbPackage package,
}) {
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (context) => _MirrorAppQuickActionsDialog(
      deviceId: deviceId,
      package: package,
    ),
  );
}

/// 投屏独立窗口的前台应用快捷操作弹窗。
/// 按照生命周期、ADB 调试、权限管理、扩展工具及网络控制进行分类呈现。
class _MirrorAppQuickActionsDialog extends ConsumerStatefulWidget {
  const _MirrorAppQuickActionsDialog({
    required this.deviceId,
    required this.package,
  });

  final String deviceId;
  final AdbPackage package;

  @override
  ConsumerState<_MirrorAppQuickActionsDialog> createState() =>
      _MirrorAppQuickActionsDialogState();
}

class _MirrorAppQuickActionsDialogState
    extends ConsumerState<_MirrorAppQuickActionsDialog> {
  late final MirrorAppQuickActionsController _controller;
  String _searchQuery = '';
  int _selectedCategoryIndex = 0;

  final List<String> _categories = [
    '全部',
    '生命周期',
    '调试运行',
    '权限控制',
    '扩展工具',
    '网络控制',
  ];

  @override
  void initState() {
    super.initState();
    _controller = MirrorAppQuickActionsController(
      ref: ref,
      context: context,
      deviceId: widget.deviceId,
      package: widget.package,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final package = widget.package;

    final dialogBg = isDark ? const Color(0xff1e1e1e) : const Color(0xffffffff);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 620,
          maxHeight: 680,
          minWidth: 460,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部应用信息栏与关闭按钮
            _buildHeader(context, package, isDark),
            const Divider(height: 1, thickness: 1),
            // 搜索与分类导航
            _buildCategoryBar(isDark),
            const Divider(height: 1, thickness: 1),
            // 操作项目列表
            Expanded(
              child: _buildActionList(context, package, isDark),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部应用头栏
  Widget _buildHeader(
    BuildContext context,
    AdbPackage package,
    bool isDark,
  ) {
    final iconPath = package.iconLocalPath;
    final hasLocalIcon =
        iconPath != null && iconPath.isNotEmpty && File(iconPath).existsSync();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          // 应用图标
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: hasLocalIcon
                  ? Image.file(
                      File(iconPath!),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        CupertinoIcons.app_badge,
                        size: 24,
                      ),
                    )
                  : const Icon(CupertinoIcons.app_badge, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          // 应用名称与包名
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        package.displayName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (package.versionName != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'v${package.versionName}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  package.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 关闭按钮
          IconButton(
            icon: const Icon(CupertinoIcons.xmark, size: 18),
            splashRadius: 18,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// 分类与搜索过滤栏
  Widget _buildCategoryBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: isDark
          ? Colors.white.withValues(alpha: 0.02)
          : Colors.black.withValues(alpha: 0.015),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 搜索框
          SizedBox(
            height: 32,
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value.trim()),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索快捷操作 (如: 重启, 调试, 权限, 清除)...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                prefixIcon: const Icon(CupertinoIcons.search, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                isDense: true,
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 分类 Chip 列表
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_categories.length, (index) {
                final isSelected = _selectedCategoryIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      _categories[index],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategoryIndex = index);
                      }
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建操作项列表
  Widget _buildActionList(
    BuildContext context,
    AdbPackage package,
    bool isDark,
  ) {
    final sections = buildMirrorAppQuickActionSections(
      context: context,
      package: package,
      controller: _controller,
    );

    // 根据分类与搜索关键字过滤
    final filteredSections = <Widget>[];
    for (final section in sections) {
      if (_selectedCategoryIndex != 0 &&
          section.categoryIndex != _selectedCategoryIndex) {
        continue;
      }

      final matchingItems = section.items.where((item) {
        if (_searchQuery.isEmpty) return true;
        return item.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (item.subtitle?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
                false);
      }).toList();

      if (matchingItems.isEmpty) continue;

      filteredSections.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(
            section.title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ),
      );

      filteredSections.add(
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 280,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 60,
          ),
          itemCount: matchingItems.length,
          itemBuilder: (context, index) {
            final item = matchingItems[index];
            return MirrorAppQuickActionItem(
              icon: item.icon,
              title: item.title,
              subtitle: item.subtitle,
              iconColor: item.iconColor,
              isDanger: item.isDanger,
              onTap: item.onTap,
            );
          },
        ),
      );
    }

    if (filteredSections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '未找到匹配的快捷操作',
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: filteredSections,
    );
  }
}
