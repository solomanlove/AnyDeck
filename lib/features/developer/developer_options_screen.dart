import 'package:flutter/material.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widget/developer_info_section.dart';
import 'widget/developer_page_header.dart';
import 'widget/developer_window_bar.dart';
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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.appColors.sunkenSurface,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部导航栏（支持 macOS 红黄绿按钮避让）
            const DeveloperWindowBar(),
            // 主体滚动区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶部大标题与徽章 (Hero Header)
                        const DeveloperPageHeader(),
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
}
