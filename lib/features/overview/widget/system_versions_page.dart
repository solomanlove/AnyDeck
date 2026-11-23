import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../widgets/dashboard_header_bar.dart';
import '../controller/system_versions_controller.dart';
import '../model/platform_distribution_type.dart';
import 'android_api_distribution_view.dart';
import 'harmony_api_distribution_view.dart';
import 'ios_version_distribution_view.dart';
import 'platform_version_switcher.dart';
import 'version_distribution_layout.dart';

/// 主窗口的系统版本资料页，复用既有三平台列表、详情、复制和链接功能。
///
/// 不要求设备连接；直接作为 Dashboard 内容使用，不包含关闭窗口按钮。
/// 版本列表与详情跟随内容区宽度排版，低窗口可纵向滚动阅读。
class SystemVersionsPage extends ConsumerWidget {
  const SystemVersionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(systemVersionsPlatformProvider);
    final theme = Theme.of(context);
    final notice = platform.localizedFlagNotice(
      Localizations.localeOf(context).languageCode,
    );
    final switcher = PlatformVersionSwitcher(
      selectedPlatform: platform,
      onPlatformChanged: ref
          .read(systemVersionsPlatformProvider.notifier)
          .select,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final compact = constraints.maxWidth < 900 * textScale;
        return VersionDistributionPageLayout(
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashboardHeaderBar(
                title: context.l10n.t('systemVersions'),
                subtitle: context.l10n.t(platform.titleL10nKey),
                trailing: compact ? null : switcher,
              ),
              if (compact)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: switcher,
                  ),
                ),
            ],
          ),
          body: switch (platform) {
            PlatformDistributionType.android =>
              const AndroidApiDistributionView(isEmbedded: true),
            PlatformDistributionType.harmony =>
              const HarmonyApiDistributionView(),
            PlatformDistributionType.ios => const IosVersionDistributionView(),
          },
          footer: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  '${context.l10n.t('lastUpdatedPrefix')}${platform.lastUpdatedDate}',
                  style: theme.textTheme.bodySmall,
                ),
                if (notice.isNotEmpty)
                  Text(
                    notice,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
