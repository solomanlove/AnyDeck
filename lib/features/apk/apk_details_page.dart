import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/window/model/desktop_chrome_policy.dart';
import '../../app/widget/app_detail_layout.dart';
import '../../core/apk/apk_install_controller.dart';
import '../../core/apk/android_package_format.dart';
import '../../core/apk/apk_window_client.dart';
import 'widgets/apk_detail_list.dart';
import 'widgets/apk_install_bar.dart';
import 'widgets/apk_summary.dart';

/// 本地 Android 安装包详情，左侧静态概况与右侧只读 Tabs 均可离线使用。
class ApkDetailsPage extends ConsumerWidget {
  const ApkDetailsPage({
    super.key,
    required this.path,
    required this.mainWindowId,
  });
  final String path;
  final String mainWindowId;
  static const tabs = {
    'libs': 'apkLibs',
    'services': 'apkServices',
    'activities': 'apkActivities',
    'receivers': 'apkReceivers',
    'providers': 'apkProviders',
    'permissions': 'apkPermissions',
    'metadata': 'apkMetadata',
    'dex': 'apkDex',
    'signatures': 'apkSignatures',
  };
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(localApkProvider(path));
    final busy = ref.watch(
      apkInstallProvider(mainWindowId).select((s) => s.busy),
    );
    void refresh() {
      ref.invalidate(localApkProvider(path));
      ref.invalidate(apkInstallProvider(mainWindowId));
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const SizedBox.shrink(),
        leadingWidth: DesktopChromePolicy.current.toolbarLeadingInset,
        title: DragToMoveArea(
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n
                    .t('apkPackageTitle')
                    .replaceAll(
                      '{format}',
                      AndroidPackageFormat.fromPath(path)?.label ?? 'APK',
                    ),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.t('apkRefresh'),
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(apkErrorText(context, error)),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: refresh,
                  child: Text(context.l10n.t('apkRefresh')),
                ),
              ],
            ),
          ),
        ),
        data: (info) {
          final summaryBackground = Theme.of(
            context,
          ).colorScheme.surfaceContainerLow;
          final detailTabs = {
            if (info.format == 'AAB') 'modules': 'apkModules',
            if (info.format == 'APKS' || info.format == 'XAPK')
              'archiveEntries': 'apkArchiveEntries',
            if (info.rows('containerMetadata').isNotEmpty)
              'containerMetadata': 'apkContainerMetadata',
            ...tabs,
          };
          final tabData = <AppDetailTabData>[
            AppDetailTabData(
              id: 'install',
              title: context.l10n.t(
                info.analysisOnly ? 'apkArchiveOverview' : 'apkInstallTab',
              ),
            ),
            for (final tab in detailTabs.entries)
              AppDetailTabData(
                id: tab.key,
                title: context.l10n.t(tab.value),
                count: info.rows(tab.key).length,
              ),
          ];
          final viewData = buildLocalApkDetailViewData(
            context,
            info: info,
            path: path,
            tabs: tabData,
          );
          return Column(
            children: [
              Expanded(
                child: AppDetailView(
                  data: viewData,
                  summaryBackground: summaryBackground,
                  copyTooltip: context.l10n.t('apkCopy'),
                  tabViews: [
                    ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          context.l10n.t('apkOffline'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          context.l10n.t(
                            info.analysisOnly
                                ? info.format == 'AAB'
                                      ? 'apkBundleDescription'
                                      : 'apkArchiveDescription'
                                : 'apkInstallDescription',
                          ),
                        ),
                        if (!info.analysisOnly && !info.installable)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(context.l10n.t('apkSplit')),
                          ),
                        for (final warning
                            in info.data['warnings'] as List? ?? [])
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: SelectableText(
                              apkErrorText(context, warning),
                            ),
                          ),
                      ],
                    ),
                    for (final tab in detailTabs.keys)
                      ApkDetailList(
                        rows: info.rows(tab),
                        fallbackIcon: info.icon,
                        showComponentIcon: tab == 'activities',
                        note: tab == 'signatures'
                            ? context.l10n.t(
                                info.format == 'AAB'
                                    ? 'apkBundleSignatureNote'
                                    : 'apkSignatureNote',
                              )
                            : tab == 'permissions'
                            ? context.l10n.t('apkPermissionNote')
                            : null,
                      ),
                  ],
                ),
              ),
              if (!info.analysisOnly)
                ApkInstallBar(
                  info: info,
                  path: path,
                  mainWindowId: mainWindowId,
                ),
            ],
          );
        },
      ),
    );
  }
}
