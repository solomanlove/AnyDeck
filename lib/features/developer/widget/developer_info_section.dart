import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import 'developer_section_card.dart';

/// 运行时与系统环境信息展示卡片。
///
/// 集中展示当前操作系统、构建类型、Flutter/Dart 运行环境、窗口分辨率等核心参数，
/// 方便开发与测试人员在调试时快速确认当前运行环境。
class DeveloperInfoSection extends ConsumerWidget {
  const DeveloperInfoSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final media = MediaQuery.of(context);

    final buildMode = kDebugMode
        ? 'Debug (调试模式)'
        : (kProfileMode ? 'Profile (性能分析)' : 'Release (正式发布)');

    final osInfo = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

    return DeveloperSectionCard(
      title: '环境与运行时信息',
      subtitle: 'System & Runtime Environment',
      icon: Icons.computer_rounded,
      children: [
        _buildInfoGrid(context, [
          _InfoEntry(label: '构建模式 (Build Mode)', value: buildMode),
          _InfoEntry(label: '操作系统 (OS)', value: osInfo),
          _InfoEntry(
            label: '窗口尺寸 (Logical Size)',
            value: '${media.size.width.toStringAsFixed(0)} × ${media.size.height.toStringAsFixed(0)} pt',
          ),
          _InfoEntry(
            label: '像素缩放比 (Device Pixel Ratio)',
            value: '${media.devicePixelRatio.toStringAsFixed(2)}x',
          ),
          _InfoEntry(
            label: 'Dart VM 版本',
            value: Platform.version.split(' ').first,
          ),
          _InfoEntry(
            label: '当前应用语言',
            value: settings.language.code.toUpperCase(),
          ),
          _InfoEntry(
            label: '外观模式 (Theme Mode)',
            value: settings.themeMode.name,
          ),
          _InfoEntry(
            label: '快捷键 (Shortcut Key)',
            value: '⌘${settings.showWindowShortcutKey.toUpperCase()}',
          ),
        ]),
      ],
    );
  }

  /// 构建双列/自适应排版的参数网格
  Widget _buildInfoGrid(BuildContext context, List<_InfoEntry> entries) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: entries.map((entry) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              width: 350,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : const Color(0xfff8fafc),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color(0xff334155).withValues(alpha: 0.4)
                      : const Color(0xfff1f5f9),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    entry.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: Platform.isMacOS ? 'SF Pro Text' : null,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }).toList(),
    );
  }
}

/// 单个信息键值项
class _InfoEntry {
  const _InfoEntry({required this.label, required this.value});

  final String label;
  final String value;
}
