part of '../dashboard_screen.dart';

/// 设置仅负责目录编排；分类切换与搜索状态由独立 Workspace 管理。
class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardHeaderBar(
          title: context.l10n.t('settings'),
          subtitle: context.l10n.t('settingsDesc'),
        ),
        Expanded(
          child: SettingsWorkspace(
            items: [
              ..._catalogItems(context, ref),
              ..._mediaItems(context, ref),
            ],
            cardBuilder: (title, children) =>
                _buildSectionCard(context, title: title, children: children),
          ),
        ),
      ],
    );
  }
}
