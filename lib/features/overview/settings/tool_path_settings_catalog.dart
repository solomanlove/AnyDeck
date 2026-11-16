import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../devices/controller/platform_tools_controller.dart';
import '../widget/tool_path_setting_field.dart';
import 'settings_item.dart';

/// 核心工具路径与目录操作统一纳入设置目录，供分类导航和全局搜索复用。
List<SettingsItem> buildToolPathSettingsItems(BuildContext context) => [
  for (final tool in configurableToolNames)
    SettingsItem(
      id: 'toolPath-$tool',
      category: SettingsCategory.dependencies,
      section: context.l10n.t('toolPathTitle-$tool'),
      title: context.l10n.t('toolPathTitle-$tool'),
      description: context.l10n.t('toolPathDescription-$tool'),
      keywords: '$tool ${context.l10n.t('toolPathKeywords')}',
      searchLabels: [
        context.l10n.t('toolPathExecutable'),
        context.l10n.t('toolPathChoose'),
        context.l10n.t('toolPathOpenDirectory'),
        context.l10n.t('toolPathOpenTerminal'),
      ],
      child: _ToolPathSetting(toolName: tool),
    ),
];

/// 将纯编辑器与全局设置连接；目录操作始终使用已应用路径，避免使用未保存草稿。
class _ToolPathSetting extends ConsumerWidget {
  const _ToolPathSetting({required this.toolName});

  final String toolName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.toolPaths[toolName] ?? '',
      ),
    );
    return ToolPathSettingField(
      key: ValueKey('tool-setting-$toolName'),
      toolName: toolName,
      value: path,
      resolvedPath: PlatformToolsController.resolveToolExecutable(ref, toolName),
      onChanged: (value) =>
          ref.read(appSettingsProvider.notifier).setToolPath(toolName, value),
      onOpen: (terminal) => PlatformToolsController.openToolDirectory(
        context,
        ref,
        toolName,
        terminal: terminal,
      ),
    );
  }
}
