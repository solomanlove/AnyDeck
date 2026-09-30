import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/settings/app_settings_controller.dart';
import '../../app/widget/app_toast.dart';
import 'widget/developer_info_section.dart';
import 'widget/developer_tools_section.dart';

/// 开发者选项页面主视图。
///
/// 集中承载应用的所有调试工具、测试功能入口和运行时状态监测，
/// 后续新增的所有调试页面和测试实验功能均可注册在此页面中。
class DeveloperOptionsScreen extends ConsumerWidget {
  /// 创建开发者选项主页面
  const DeveloperOptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const brandGreen = Color(0xff09c47c);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xff0f172a) : const Color(0xfff8fafc),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部导航栏（支持 macOS 红黄绿按钮避让）
            _buildWindowTopBar(context, ref, settings, controller, brandGreen),
            // 主体滚动区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶部大标题与徽章 (Hero Header)
                        _buildPageHeroHeader(context, brandGreen),
                        const SizedBox(height: 24),
                        // 1. 系统与环境信息
                        const DeveloperInfoSection(),
                        const SizedBox(height: 20),
                        // 2. 核心调试工具与测试功能
                        const DeveloperToolsSection(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建顶部导航栏，预留 macOS 红黄绿交通灯避让空间并提供胶囊返回按钮与状态开关
  Widget _buildWindowTopBar(
    BuildContext context,
    WidgetRef ref,
    dynamic settings,
    AppSettingsController controller,
    Color brandGreen,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final leftPadding = Platform.isMacOS ? 80.0 : 20.0;

    return Container(
      height: 52,
      padding: EdgeInsets.only(left: leftPadding, right: 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1e293b).withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
          ),
        ),
      ),
      child: Row(
        children: [
          // 胶囊返回按钮
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff334155).withValues(alpha: 0.5) : const Color(0xfff1f5f9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? const Color(0xff475569) : const Color(0xffe2e8f0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.chevron_back,
                    size: 15,
                    color: isDark ? Colors.white70 : const Color(0xff334155),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.t('settings'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xff334155),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          // 面包屑分隔与弱化标题
          Text(
            '/',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? const Color(0xff475569) : const Color(0xffcbd5e1),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            context.l10n.t('developerOptions'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : const Color(0xff64748b),
            ),
          ),
          const Spacer(),
          // 开发者模式状态开关胶囊
          Container(
            padding: const EdgeInsets.only(left: 10, right: 6, top: 2, bottom: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff334155).withValues(alpha: 0.4) : const Color(0xfff8fafc),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xff475569) : const Color(0xffe2e8f0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: settings.developerModeEnabled ? brandGreen : Colors.grey,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  context.l10n.t('developerModeSwitch'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : const Color(0xff475569),
                  ),
                ),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.75,
                  child: Switch.adaptive(
                    activeTrackColor: brandGreen.withValues(alpha: 0.5),
                    activeThumbColor: brandGreen,
                    value: settings.developerModeEnabled,
                    onChanged: (val) {
                      controller.setDeveloperModeEnabled(val);
                      if (!val) {
                        AppToast.show(context, '已关闭开发者模式，设置中已隐藏入口', type: AppToastType.info);
                      } else {
                        AppToast.show(context, '开发者模式已开启', type: AppToastType.success);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 页面顶部大标题与徽章 (Hero Header)
  Widget _buildPageHeroHeader(BuildContext context, Color brandGreen) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 质感大图标容器
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  brandGreen.withValues(alpha: 0.2),
                  brandGreen.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: brandGreen.withValues(alpha: 0.3),
                width: 1.2,
              ),
            ),
            child: Center(
              child: Icon(
                CupertinoIcons.wrench_fill,
                color: brandGreen,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 标题与副标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      context.l10n.t('developerOptions'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: brandGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: brandGreen.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'DEBUG & LABS',
                        style: TextStyle(
                          color: brandGreen,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '应用底层诊断、UI组件预览、网络探测与实验性功能集合',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
