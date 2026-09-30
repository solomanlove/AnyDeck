import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/adb/adb_environment_service.dart';
import '../../../core/environment/connection_environment_service.dart';
import '../../devices/widgets/adb_environment_dialog.dart';
import '../../devices/widgets/platform_environment_guide_dialog.dart';
import 'developer_section_card.dart';

/// 开发者选项 - 全平台连接环境与工具诊断卡片。
///
/// 集中展示 Android (ADB)、纯血鸿蒙 (HDC) 以及苹果 iOS (go-ios) 三大工具链在
/// 本机的就绪状态、绝对路径与已探测到的版本详情，并提供一键调起安装引导与模拟测试入口。
class DeveloperConnectionEnvironmentCard extends ConsumerStatefulWidget {
  const DeveloperConnectionEnvironmentCard({super.key});

  @override
  ConsumerState<DeveloperConnectionEnvironmentCard> createState() =>
      _DeveloperConnectionEnvironmentCardState();
}

class _DeveloperConnectionEnvironmentCardState
    extends ConsumerState<DeveloperConnectionEnvironmentCard> {
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    // 首次加载时自检全端环境
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recheckAll();
    });
  }

  /// 重新检测全平台环境
  Future<void> _recheckAll() async {
    setState(() => _isChecking = true);
    try {
      await Future.wait([
        ref.read(connectionEnvironmentProvider.notifier).checkAll(),
        ref.read(adbEnvironmentProvider.notifier).check(),
      ]);
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final envMap = ref.watch(connectionEnvironmentProvider);
    final adbEnv = ref.watch(adbEnvironmentProvider);

    final harmonyInfo = envMap[TargetPlatformType.harmony];
    final iosInfo = envMap[TargetPlatformType.ios];

    return DeveloperSectionCard(
      title: '多端连接环境与工具诊断',
      subtitle: 'Multi-Platform (Android / HarmonyOS / iOS) Toolchain Diagnosis',
      icon: CupertinoIcons.layers_alt_fill,
      trailing: TextButton.icon(
        icon: _isChecking
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(CupertinoIcons.refresh, size: 14),
        label: const Text('重新检测全部'),
        onPressed: _isChecking ? null : _recheckAll,
      ),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : const Color(0xfff8fafc),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark
                  ? const Color(0xff334155).withValues(alpha: 0.4)
                  : const Color(0xffe2e8f0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Android (ADB)
              _buildToolRow(
                context,
                title: 'Android (ADB 调试桥)',
                icon: Icons.android_rounded,
                isReady: adbEnv.isReady,
                version: adbEnv.version.isNotEmpty ? adbEnv.version : 'ADB 未就绪',
                path: adbEnv.adbPath.isNotEmpty ? adbEnv.adbPath : '未找到 adb 命令',
                onGuide: () => PlatformEnvironmentGuideDialog.show(
                  context,
                  initialPlatform: TargetPlatformType.android,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // 2. 纯血鸿蒙 (HDC)
              _buildToolRow(
                context,
                title: '纯血鸿蒙 (HarmonyOS NEXT HDC)',
                icon: Icons.hub_rounded,
                isReady: harmonyInfo?.isReady ?? false,
                version: harmonyInfo?.version.isNotEmpty == true
                    ? harmonyInfo!.version
                    : (harmonyInfo?.errorMessage.isNotEmpty == true
                        ? harmonyInfo!.errorMessage
                        : 'HDC 未就绪 / 未安装'),
                path: harmonyInfo?.executablePath.isNotEmpty == true
                    ? harmonyInfo!.executablePath
                    : '未在系统 PATH 或常用路径找到 hdc',
                onGuide: () => PlatformEnvironmentGuideDialog.show(
                  context,
                  initialPlatform: TargetPlatformType.harmony,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // 3. 苹果 iOS (go-ios)
              _buildToolRow(
                context,
                title: '苹果 iOS (go-ios 通信工具)',
                icon: Icons.apple_rounded,
                isReady: iosInfo?.isReady ?? false,
                version: iosInfo?.version.isNotEmpty == true
                    ? iosInfo!.version
                    : (iosInfo?.errorMessage.isNotEmpty == true
                        ? iosInfo!.errorMessage
                        : 'go-ios 未就绪 / 未安装'),
                path: iosInfo?.executablePath.isNotEmpty == true
                    ? iosInfo!.executablePath
                    : '未找到 go-ios 或 ios CLI 工具',
                onGuide: () => PlatformEnvironmentGuideDialog.show(
                  context,
                  initialPlatform: TargetPlatformType.ios,
                ),
              ),

              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // 底部快捷操作与模拟测试
              Text(
                '多端环境引导与测试操作：',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff09c47c),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(CupertinoIcons.device_phone_portrait, size: 16),
                    label: const Text('调出多端环境与安装引导'),
                    onPressed: () async {
                      await PlatformEnvironmentGuideDialog.show(context);
                      _recheckAll();
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xff0284c7),
                      side: const BorderSide(color: Color(0xff0284c7)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    icon: const Icon(Icons.hub_rounded, size: 15),
                    label: const Text('鸿蒙 HDC 引导测试'),
                    onPressed: () async {
                      ref
                          .read(connectionEnvironmentProvider.notifier)
                          .simulateMissing(TargetPlatformType.harmony);
                      await PlatformEnvironmentGuideDialog.show(
                        context,
                        initialPlatform: TargetPlatformType.harmony,
                      );
                      _recheckAll();
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.purple,
                      side: const BorderSide(color: Colors.purple),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    icon: const Icon(Icons.apple_rounded, size: 15),
                    label: const Text('iOS 引导测试'),
                    onPressed: () async {
                      ref
                          .read(connectionEnvironmentProvider.notifier)
                          .simulateMissing(TargetPlatformType.ios);
                      await PlatformEnvironmentGuideDialog.show(
                        context,
                        initialPlatform: TargetPlatformType.ios,
                      );
                      _recheckAll();
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    icon: const Icon(Icons.android_rounded, size: 15),
                    label: const Text('ADB 缺失弹窗测试'),
                    onPressed: () async {
                      ref.read(adbEnvironmentProvider.notifier).simulateMissing();
                      await AdbEnvironmentDialog.show(context);
                      _recheckAll();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '说明：点击对应平台的“引导测试”可直接查看当用户未配置该工具时的完整指引弹窗（包含官网下载直达、Homebrew 终端命令及手机端 USB 调试与开发者模式开启教程）。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建各工具单行信息
  Widget _buildToolRow(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isReady,
    required String version,
    required String path,
    required VoidCallback onGuide,
  }) {
    final theme = Theme.of(context);
    final statusColor = isReady ? const Color(0xff09c47c) : Colors.orange;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurface),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isReady ? '已就绪' : '未就绪',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              SelectableText(
                '版本: $version',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                '路径: $path',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onGuide,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('安装/配置引导', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }
}
