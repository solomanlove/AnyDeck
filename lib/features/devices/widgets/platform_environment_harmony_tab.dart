part of 'platform_environment_guide_dialog.dart';

/// 展示鸿蒙设备所需的 HDC 环境、工具下载入口和连接步骤。
extension _HarmonyEnvironmentTab on _PlatformEnvironmentGuideDialogState {
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
            readyText:
                '纯血鸿蒙 HDC 工具链已就绪\n版本: ${info?.version ?? ""}\n路径: ${info?.executablePath ?? ""}',
            missingText: context.l10n.t('harmonyEnvDesc'),
          ),
          const SizedBox(height: 14),

          // 两种官方发行包都包含 HDC，窄窗口下下载按钮自动换行。
          _buildSectionHeader(context, context.l10n.t('harmonyInstallOptions')),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.t('harmonyInstallOptionsDesc'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(CupertinoIcons.link, size: 16),
                      label: Text(
                        context.l10n.t('harmonyOpenCommandLineTools'),
                      ),
                      onPressed: () => widget.onOpenHarmonyDownload(
                        ConnectionEnvironmentService
                            .commandLineToolsDownloadUrl,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(CupertinoIcons.link, size: 16),
                      label: Text(context.l10n.t('harmonyOpenDevEco')),
                      onPressed: () => widget.onOpenHarmonyDownload(
                        ConnectionEnvironmentService.devecoStudioDownloadUrl,
                      ),
                    ),
                  ],
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
            Platform.isWindows
                ? r'set "PATH=%USERPROFILE%\command-line-tools\sdk\default\openharmony\toolchains;%PATH%"'
                : r'export PATH="$HOME/command-line-tools/sdk/default/openharmony/toolchains:$PATH"',
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
                    type: result.isReady
                        ? AppToastType.success
                        : AppToastType.warning,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
