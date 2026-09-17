import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/l10n/app_localizations.dart';
import '../../core/apk/apk_install_controller.dart';
import '../../core/apk/apk_window_client.dart';
import 'widgets/apk_detail_list.dart';
import 'widgets/apk_install_bar.dart';
import 'widgets/apk_summary.dart';

/// 本地 APK 详情，左侧静态概况与右侧只读 Tabs 均可离线使用。
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
        leadingWidth: 80,
        title: DragToMoveArea(
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(context.l10n.t('apkTitle')),
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
        data: (info) => Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 290,
                    child: ApkSummary(info: info, path: path),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: DefaultTabController(
                      length: tabs.length + 1,
                      child: Column(
                        children: [
                          TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: [
                              Tab(text: context.l10n.t('apkInstallTab')),
                              for (final tab in tabs.entries)
                                Tab(
                                  text:
                                      '${context.l10n.t(tab.value)} (${info.rows(tab.key).length})',
                                ),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                ListView(
                                  padding: const EdgeInsets.all(24),
                                  children: [
                                    Text(
                                      context.l10n.t('apkOffline'),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineSmall,
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      context.l10n.t('apkInstallDescription'),
                                    ),
                                    if (!info.installable)
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
                                for (final tab in tabs.keys)
                                  ApkDetailList(
                                    rows: info.rows(tab),
                                    fallbackIcon: info.icon,
                                    showComponentIcon: tab == 'activities',
                                    note: tab == 'signatures'
                                        ? context.l10n.t('apkSignatureNote')
                                        : tab == 'permissions'
                                        ? context.l10n.t('apkPermissionNote')
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ApkInstallBar(info: info, path: path, mainWindowId: mainWindowId),
          ],
        ),
      ),
    );
  }
}
