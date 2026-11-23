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
/// 版本列表与详情跟随内容区宽度排版，标题、平台切换和更新时间固定。
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
    final footerText = Wrap(
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final shortWindow = constraints.maxHeight < 240 * textScale;
        final separateSwitcher =
            !shortWindow && constraints.maxWidth < 900 * textScale;
        // 控制台展开后，平台选项和标题共用一行，给可滚动的正文留出高度。
        final inlineSwitcher = shortWindow
            ? ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .6,
                ),
                child: FittedBox(fit: BoxFit.scaleDown, child: switcher),
              )
            : switcher;
        return VersionDistributionPageLayout(
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashboardHeaderBar(
                title: context.l10n.t('systemVersions'),
                subtitle: context.l10n.t(platform.titleL10nKey),
                height: shortWindow ? 48 : 72,
                trailing: separateSwitcher ? null : inlineSwitcher,
              ),
              if (separateSwitcher)
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
            padding: EdgeInsets.symmetric(
              horizontal: 28,
              vertical: shortWindow ? 4 : 10,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            // 页脚先按可用宽度换行，仅在极矮窗口装不下大字号说明时缩放。
            child: shortWindow
                ? LayoutBuilder(
                    builder: (context, footerConstraints) => ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .4,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(
                          width: footerConstraints.maxWidth,
                          child: footerText,
                        ),
                      ),
                    ),
                  )
                : footerText,
          ),
        );
      },
    );
  }
}
