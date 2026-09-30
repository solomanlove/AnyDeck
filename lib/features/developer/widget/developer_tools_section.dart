import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/widget/app_toast.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../overview/widget/android_version_distribution_launcher.dart';
import 'developer_connection_environment_card.dart';
import 'developer_section_card.dart';

/// 核心调试工具与测试功能板块。
///
/// 包含多端连接环境诊断、Toast 预览、系统通知推送、独立窗口调起、缓存统计等实用调试能力，
/// 并为后续新增调试入口和测试功能提供模块化扩展支持。
class DeveloperToolsSection extends ConsumerStatefulWidget {
  const DeveloperToolsSection({super.key});

  @override
  ConsumerState<DeveloperToolsSection> createState() => _DeveloperToolsSectionState();
}

class _DeveloperToolsSectionState extends ConsumerState<DeveloperToolsSection> {
  int _prefKeysCount = 0;
  bool _isLoadingPrefs = false;

  @override
  void initState() {
    super.initState();
    _loadPrefsCount();
  }

  /// 统计 SharedPreferences 键值数量
  Future<void> _loadPrefsCount() async {
    setState(() => _isLoadingPrefs = true);
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _prefKeysCount = prefs.getKeys().length;
        _isLoadingPrefs = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xff09c47c);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 多端连接环境与工具诊断
        const DeveloperConnectionEnvironmentCard(),
        const SizedBox(height: 20),

        // 2. 界面与交互测试
        DeveloperSectionCard(
          title: '界面与交互测试',
          subtitle: 'UI, Toast & Multi-Window Testing',
          icon: CupertinoIcons.sparkles,
          children: [
            _buildToastTester(context),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _buildActionButtons(context),
          ],
        ),
        const SizedBox(height: 20),

        // 3. 存储与数据调试
        DeveloperSectionCard(
          title: '存储与缓存调试',
          subtitle: 'Local Storage & Memory Cache',
          icon: CupertinoIcons.archivebox_fill,
          children: [
            _buildStorageDebug(context),
          ],
        ),
        const SizedBox(height: 20),

        // 4. 未来扩展插槽（后续新增的调试与测试页面均可在此注册）
        DeveloperSectionCard(
          title: '测试功能与调试扩展中心',
          subtitle: 'Custom Debug Entrypoints & Experimental Features',
          icon: CupertinoIcons.plus_app_fill,
          children: [
            _buildExtensionPlaceholder(context, brandGreen),
          ],
        ),
      ],
    );
  }


  /// 全局 Toast 样式快速测试器
  Widget _buildToastTester(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '全局 Toast 预览测试：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildDebugChip(
              context,
              label: '成功提示 (Success)',
              color: const Color(0xff09c47c),
              onTap: () => AppToast.show(context, '操作成功：数据已保存！', type: AppToastType.success),
            ),
            _buildDebugChip(
              context,
              label: '信息提示 (Info)',
              color: const Color(0xff3b82f6),
              onTap: () => AppToast.show(context, '提示：当前为测试环境', type: AppToastType.info),
            ),
            _buildDebugChip(
              context,
              label: '警告提示 (Warning)',
              color: const Color(0xfff59e0b),
              onTap: () => AppToast.show(context, '警告：未检测到目标设备', type: AppToastType.warning),
            ),
            _buildDebugChip(
              context,
              label: '错误提示 (Error)',
              color: const Color(0xffef4444),
              onTap: () => AppToast.show(context, '错误：网络连接超时 (CODE: 504)', type: AppToastType.error),
            ),
          ],
        ),
      ],
    );
  }

  /// 窗口与系统通知测试按钮
  Widget _buildActionButtons(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff09c47c),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          icon: const Icon(CupertinoIcons.macwindow, size: 16),
          label: const Text('打开 Android 版本分布独立窗口'),
          onPressed: () => openAndroidVersionDistributionWindow(context),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(CupertinoIcons.bell_fill, size: 16),
          label: const Text('发送测试系统通知 (macOS Notification)'),
          onPressed: () async {
            if (Platform.isMacOS) {
              final bridge = ref.read(macNotificationBridgeProvider);
              await bridge.showNotification(
                id: 'debug_test_${DateTime.now().millisecondsSinceEpoch}',
                title: 'AnyDeck 开发者调试',
                body: '收到一条测试系统通知，推送通道运行正常。',
              );
              if (context.mounted) {
                AppToast.show(context, '已发送测试系统通知');
              }
            } else {
              AppToast.show(context, '当前系统不支持 macOS 原生通知通道', type: AppToastType.info);
            }
          },
        ),
      ],
    );
  }

  /// 存储与本地偏好项统计
  Widget _buildStorageDebug(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'SharedPreferences 本地持久化键数: $_prefKeysCount 个',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        TextButton.icon(
          icon: _isLoadingPrefs
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(CupertinoIcons.arrow_clockwise, size: 14),
          label: const Text('刷新统计'),
          onPressed: _isLoadingPrefs ? null : _loadPrefsCount,
        ),
      ],
    );
  }

  /// 扩展插槽说明组件
  Widget _buildExtensionPlaceholder(BuildContext context, Color brandGreen) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: brandGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brandGreen.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.hammer, color: brandGreen, size: 18),
              const SizedBox(width: 8),
              Text(
                '调试入口与测试功能扩展说明',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: brandGreen,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '这里是 AnyDeck 的开发者调试与测试功能统一集合中心。'
            '以后所有新增的调试功能、专项测试页面、协议分析工具或模拟器实验，均可直接在此页面追加组件或二级路由跳转。',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 构建测试操作 Chip
  Widget _buildDebugChip(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
