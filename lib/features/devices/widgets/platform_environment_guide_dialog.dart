import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/app_toast.dart';
import '../../../core/adb/adb_environment_service.dart';
import '../../../core/environment/connection_environment_service.dart';

/// 多端连接环境自检与安装引导对话框。
///
/// 集中展示 Android (ADB)、纯血鸿蒙 (HDC) 以及苹果 iOS (go-ios) 三大平台的连接工具
/// 就绪状态、执行路径、版本号，并在工具缺失时提供官方下载、终端安装命令与真机授权操作指南。
class PlatformEnvironmentGuideDialog extends ConsumerStatefulWidget {
  const PlatformEnvironmentGuideDialog({
    super.key,
    this.initialPlatform = TargetPlatformType.android,
  });

  /// 初始激活的平台 Tab
  final TargetPlatformType initialPlatform;

  /// 便捷静态展示方法
  static Future<void> show(
    BuildContext context, {
    TargetPlatformType initialPlatform = TargetPlatformType.android,
    bool barrierDismissible = true,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => PlatformEnvironmentGuideDialog(
        initialPlatform: initialPlatform,
      ),
    );
  }

  @override
  ConsumerState<PlatformEnvironmentGuideDialog> createState() =>
      _PlatformEnvironmentGuideDialogState();
}

class _PlatformEnvironmentGuideDialogState
    extends ConsumerState<PlatformEnvironmentGuideDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initialIndex = switch (widget.initialPlatform) {
      TargetPlatformType.android => 0,
      TargetPlatformType.harmony => 1,
      TargetPlatformType.ios => 2,
    };
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIndex,
    );

    // 打开弹窗时静默重新探测所有环境
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(connectionEnvironmentProvider.notifier).checkAll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final envMap = ref.watch(connectionEnvironmentProvider);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.device_phone_portrait, size: 22),
              const SizedBox(width: 10),
              Text(
                context.l10n.t('platformEnvTitle'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.t('platformEnvDesc'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          // 平台切换 TabBar
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                  : const Color(0xfff1f5f9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: isDark ? const Color(0xff334155) : Colors.white,
                borderRadius: BorderRadius.circular(7),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              tabs: [
                _buildTabItem(context, 'Android (ADB)', envMap[TargetPlatformType.android]),
                _buildTabItem(context, '纯血鸿蒙 (HDC)', envMap[TargetPlatformType.harmony]),
                _buildTabItem(context, '苹果 iOS (go-ios)', envMap[TargetPlatformType.ios]),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        height: 440,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildAndroidTab(context, envMap[TargetPlatformType.android]),
            _buildHarmonyTab(context, envMap[TargetPlatformType.harmony]),
            _buildIosTab(context, envMap[TargetPlatformType.ios]),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(CupertinoIcons.refresh, size: 15),
          label: Text(context.l10n.t('recheckAll')),
          onPressed: () {
            ref.read(connectionEnvironmentProvider.notifier).checkAll();
            ref.read(adbEnvironmentProvider.notifier).check();
            AppToast.show(context, '正在重新检测全端环境...');
          },
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('close')),
        ),
      ],
    );
  }

  /// 构建带状态角标的 Tab 标题
  Widget _buildTabItem(BuildContext context, String title, PlatformEnvironmentInfo? info) {
    final isReady = info?.isReady ?? false;
    final isMissing = info?.isMissing ?? false;

    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isReady
                  ? const Color(0xff09c47c)
                  : (isMissing ? Colors.orange : Colors.grey),
            ),
          ),
          const SizedBox(width: 6),
          Text(title),
        ],
      ),
    );
  }

  /// 1. Android (ADB) 内容视图
  Widget _buildAndroidTab(BuildContext context, PlatformEnvironmentInfo? info) {
    final theme = Theme.of(context);
    final adbEnv = ref.watch(adbEnvironmentProvider);
    final isReady = adbEnv.isReady;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 状态卡片
          _buildStatusBanner(
            context,
            isReady: isReady,
            readyText: 'ADB 调试桥环境已就绪\n${adbEnv.version}\n路径: ${adbEnv.adbPath}',
            missingText: context.l10n.t('adbEnvironmentMissingDesc'),
          ),
          const SizedBox(height: 14),

          // 一键下载 Google 官方 Platform-Tools
          if (!isReady) ...[
            _buildSectionHeader(context, '方式一：一键下载官方 Platform-Tools（推荐）'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.t('adbOneClickDownloadDesc'),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    icon: const Icon(CupertinoIcons.cloud_download, size: 16),
                    label: Text(context.l10n.t('adbOneClickDownloadAction')),
                    onPressed: () {
                      ref.read(adbEnvironmentProvider.notifier).downloadAndInstall();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // 方式二：终端 Homebrew 安装
          _buildSectionHeader(context, '方式二：通过 Homebrew 或包管理器安装'),
          const SizedBox(height: 8),
          _buildCodeBlock(context, 'brew install android-platform-tools'),
          const SizedBox(height: 14),

          // 手机端连接指南
          _buildSectionHeader(context, '真机 USB 调试开启指引：'),
          const SizedBox(height: 6),
          _buildGuideStep('1. 进入手机「设置 -> 关于手机」，连击“版本号”开启开发者选项；'),
          _buildGuideStep('2. 返回「设置 -> 系统和更新 -> 开发者选项」，开启「USB 调试」；'),
          _buildGuideStep('3. 用数据线连接电脑，在手机屏幕弹出框中勾选“始终允许此电脑进行调试”。'),
        ],
      ),
    );
  }

  /// 2. 纯血鸿蒙 (HDC) 内容视图
  Widget _buildHarmonyTab(BuildContext context, PlatformEnvironmentInfo? info) {
    final theme = Theme.of(context);
    final isReady = info?.isReady ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 状态卡片
          _buildStatusBanner(
            context,
            isReady: isReady,
            readyText: '纯血鸿蒙 HDC 工具链已就绪\n版本: ${info?.version ?? ""}\n路径: ${info?.executablePath ?? ""}',
            missingText: context.l10n.t('harmonyEnvDesc'),
          ),
          const SizedBox(height: 14),

          // 官方推荐安装：DevEco Studio
          _buildSectionHeader(context, context.l10n.t('harmonyInstallRecommend')),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.t('harmonyInstallRecommendDesc'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  icon: const Icon(CupertinoIcons.link, size: 16),
                  label: Text(context.l10n.t('harmonyOpenDevEco')),
                  onPressed: () {
                    ConnectionEnvironmentService.openUrl(
                      ConnectionEnvironmentService.devecoStudioDownloadUrl,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 终端环境变量配置
          _buildSectionHeader(context, context.l10n.t('harmonyCliGuide')),
          const SizedBox(height: 8),
          _buildCodeBlock(
            context,
            Platform.isMacOS
                ? 'export PATH=\$PATH:~/Library/Huawei/Sdk/openharmony/toolchains'
                : 'set PATH=%PATH%;%LOCALAPPDATA%\\Huawei\\Sdk\\openharmony\\toolchains',
          ),
          const SizedBox(height: 14),

          // 真机连接设置要求
          _buildSectionHeader(context, context.l10n.t('harmonyDeviceGuide')),
          const SizedBox(height: 6),
          _buildGuideStep(context.l10n.t('harmonyDeviceStep1')),
          _buildGuideStep(context.l10n.t('harmonyDeviceStep2')),
          _buildGuideStep(context.l10n.t('harmonyDeviceStep3')),
          const SizedBox(height: 12),

          // 单独重检按钮
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.refresh, size: 14),
              label: const Text('重新检测 HDC'),
              onPressed: () async {
                final result = await ref
                    .read(connectionEnvironmentProvider.notifier)
                    .checkPlatform(TargetPlatformType.harmony);
                if (context.mounted) {
                  AppToast.show(
                    context,
                    result.isReady ? '纯血鸿蒙 HDC 环境已就绪！' : '仍未检测到可用 HDC',
                    type: result.isReady ? AppToastType.success : AppToastType.warning,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 3. 苹果 iOS (go-ios) 内容视图
  Widget _buildIosTab(BuildContext context, PlatformEnvironmentInfo? info) {
    final theme = Theme.of(context);
    final isReady = info?.isReady ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 状态卡片
          _buildStatusBanner(
            context,
            isReady: isReady,
            readyText: '苹果 iOS (go-ios) 工具链已就绪\n版本: ${info?.version ?? ""}\n路径: ${info?.executablePath ?? ""}',
            missingText: context.l10n.t('iosEnvDesc'),
          ),
          const SizedBox(height: 14),

          // 官方推荐安装方式：Homebrew
          _buildSectionHeader(context, context.l10n.t('iosInstallRecommend')),
          const SizedBox(height: 6),
          Text(
            context.l10n.t('iosInstallRecommendDesc'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _buildCodeBlock(context, 'brew install danielpaulus/tap/game-ci-tools'),
          const SizedBox(height: 14),

          // 备选安装：GitHub Releases
          _buildSectionHeader(context, context.l10n.t('iosInstallManual')),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              icon: const Icon(CupertinoIcons.link, size: 16),
              label: Text(context.l10n.t('iosOpenReleases')),
              onPressed: () {
                ConnectionEnvironmentService.openUrl(
                  ConnectionEnvironmentService.goIosReleasesUrl,
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // 真机连接与授权要求
          _buildSectionHeader(context, context.l10n.t('iosDeviceGuide')),
          const SizedBox(height: 6),
          _buildGuideStep(context.l10n.t('iosDeviceStep1')),
          _buildGuideStep(context.l10n.t('iosDeviceStep2')),
          _buildGuideStep(context.l10n.t('iosDeviceStep3')),
          const SizedBox(height: 12),

          // 单独重检按钮
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.refresh, size: 14),
              label: const Text('重新检测 iOS 工具'),
              onPressed: () async {
                final result = await ref
                    .read(connectionEnvironmentProvider.notifier)
                    .checkPlatform(TargetPlatformType.ios);
                if (context.mounted) {
                  AppToast.show(
                    context,
                    result.isReady ? '苹果 iOS (go-ios) 环境已就绪！' : '仍未检测到可用 go-ios',
                    type: result.isReady ? AppToastType.success : AppToastType.warning,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 状态顶部 Banner 卡片
  Widget _buildStatusBanner(
    BuildContext context, {
    required bool isReady,
    required String readyText,
    required String missingText,
  }) {
    final theme = Theme.of(context);
    final color = isReady ? const Color(0xff09c47c) : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isReady
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.exclamationmark_triangle_fill,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isReady ? context.l10n.t('envReady') : context.l10n.t('envMissing'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isReady ? readyText : missingText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: isReady ? 'monospace' : null,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 板块标题
  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
    );
  }

  /// 代码块与复制按钮
  Widget _buildCodeBlock(BuildContext context, String code) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal_rounded, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 16),
            tooltip: context.l10n.t('adbCopyCommand'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              AppToast.show(context, context.l10n.t('adbCopied'));
            },
          ),
        ],
      ),
    );
  }

  /// 引导步骤条目
  Widget _buildGuideStep(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, height: 1.4),
      ),
    );
  }
}
