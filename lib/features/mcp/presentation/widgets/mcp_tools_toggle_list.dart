import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/mcp_server_controller.dart';

/// MCP 注册工具集平铺列表与细粒度启用/禁用开关
class McpToolsToggleList extends ConsumerStatefulWidget {
  const McpToolsToggleList({super.key});

  @override
  ConsumerState<McpToolsToggleList> createState() => _McpToolsToggleListState();
}

class _McpToolsToggleListState extends ConsumerState<McpToolsToggleList> {
  String _selectedCategory = 'all';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = ref.watch(mcpServerProvider);
    final controller = ref.read(mcpServerProvider.notifier);
    final tools = state.registeredTools;
    final disabledNames = state.config.disabledToolNames;

    // 过滤工具列表
    final filteredTools = tools.where((tool) {
      final matchesCategory = _selectedCategory == 'all' || tool.category == _selectedCategory;
      final query = _searchQuery.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          tool.name.toLowerCase().contains(query) ||
          tool.description.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();

    const categories = [
      {'key': 'all', 'label': '全部'},
      {'key': 'device', 'label': '设备状态'},
      {'key': 'ui', 'label': 'UI/视觉'},
      {'key': 'app', 'label': '应用管理'},
      {'key': 'log', 'label': '日志排查'},
      {'key': 'file', 'label': '文件传输'},
      {'key': 'shell', 'label': '受控Shell'},
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build_circle_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '已注册的 MCP Tools 工具清单 (${tools.length} 个工具已就绪)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 220,
                  height: 36,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索工具名或描述...',
                      prefixIcon: const Icon(CupertinoIcons.search, size: 16),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '外部 AI 智能体可发现并调用以下工具。直接在下方列表开启或禁用对应工具权限：',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),
            // 分类标签栏
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat['key'];
                return ChoiceChip(
                  label: Text(cat['label']!),
                  selected: isSelected,
                  selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? theme.colorScheme.primary : null,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedCategory = cat['key']!;
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const Divider(height: 24),
            if (filteredTools.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: Text(
                    '未找到匹配的工具',
                    style: TextStyle(
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredTools.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final tool = filteredTools[index];
                  final isEnabled = !disabledNames.contains(tool.name);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getCategoryColor(tool.category).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _getCategoryColor(tool.category).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            tool.category.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _getCategoryColor(tool.category),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    tool.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  if (tool.isDangerous) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        '高危拦截',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tool.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                ),
                              ),
                              if (tool.inputSchema['properties'] != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '参数: ${(tool.inputSchema['properties'] as Map<String, dynamic>).keys.join(', ')}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch.adaptive(
                          value: isEnabled,
                          activeThumbColor: const Color(0xff09c47c),
                          activeTrackColor: const Color(0xff09c47c).withValues(alpha: 0.5),
                          onChanged: (val) {
                            controller.toggleTool(tool.name, val);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'device':
        return Colors.blue;
      case 'ui':
        return Colors.purple;
      case 'app':
        return Colors.teal;
      case 'log':
        return Colors.orange;
      case 'file':
        return Colors.amber.shade800;
      case 'shell':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
