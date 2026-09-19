part of '../dashboard_screen.dart';

/// HarmonyOS 应用专属分析页；仅展示 `bm dump` 数据，不复用 Android 详情逻辑。
class _HarmonyAppAnalysisView extends StatefulWidget {
  const _HarmonyAppAnalysisView({
    required this.package,
    required this.initialDetail,
    required this.onBack,
    required this.onReload,
  });

  final AdbPackage package;
  final HarmonyAppDetail initialDetail;
  final VoidCallback onBack;
  final Future<HarmonyAppDetail> Function() onReload;

  @override
  State<_HarmonyAppAnalysisView> createState() =>
      _HarmonyAppAnalysisViewState();
}

class _HarmonyAppAnalysisViewState extends State<_HarmonyAppAnalysisView> {
  late HarmonyAppDetail _detail;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.initialDetail;
  }

  @override
  void didUpdateWidget(covariant _HarmonyAppAnalysisView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.package.name != widget.package.name) {
      _detail = widget.initialDetail;
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final detail = await widget.onReload();
      if (!mounted) return;
      setState(() => _detail = detail);
      _showSnack(context, context.l10n.t('harmonyAnalysisRefreshSuccess'));
    } catch (error) {
      if (mounted) {
        _showSnack(
          context,
          context.l10n
              .t('harmonyAnalysisFailed')
              .replaceAll('{error}', error.toString()),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = _detail;
    final modules = detail.modules;
    final abilities = detail.abilities;
    final extensions = detail.extensions;
    final permissions = detail.permissions;
    final metadata = detail.metadata;
    final iconPath = widget.package.iconLocalPath;

    final tabs = <AppDetailTabData>[
      AppDetailTabData(
        id: 'modules',
        title: context.l10n.t('harmonyModules'),
        count: modules.length,
      ),
      AppDetailTabData(
        id: 'abilities',
        title: context.l10n.t('harmonyAbilities'),
        count: abilities.length,
      ),
      AppDetailTabData(
        id: 'extensions',
        title: context.l10n.t('harmonyExtensions'),
        count: extensions.length,
      ),
      AppDetailTabData(
        id: 'permissions',
        title: context.l10n.t('permissions'),
        count: permissions.length,
      ),
      AppDetailTabData(
        id: 'metadata',
        title: context.l10n.t('harmonyMetadata'),
        count: metadata.length,
      ),
    ];

    final fields = <AppDetailSummaryField>[
      AppDetailSummaryField(
        label: context.l10n.t('packageName'),
        value: detail.bundleName,
        copyable: true,
      ),
      AppDetailSummaryField(
        label: context.l10n.t('harmonyVersionCode'),
        value: _harmonyValue(detail.versionCode),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('harmonyCompatibleApi'),
        value: _harmonyValue(detail.compatibleApiVersion),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('harmonyTargetApi'),
        value: _harmonyValue(detail.targetApiVersion),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('harmonyCompileSdk'),
        value: _harmonyValue(detail.compileSdkVersion),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('harmonyReleaseInfo'),
        value: _joinedHarmonyValue([
          detail.releaseType,
          detail.distributionType,
        ]),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('harmonyPublisher'),
        value: _harmonyValue(
          detail.organization.isNotEmpty ? detail.organization : detail.vendor,
        ),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('harmonyInstallTime'),
        value: _formatHarmonyTime(detail.installTime),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('harmonyUpdateTime'),
        value: _formatHarmonyTime(detail.updateTime),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('appType'),
        value: detail.systemApp
            ? context.l10n.t('systemApp')
            : context.l10n.t('userApp'),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('status'),
        value: detail.enabled
            ? context.l10n.t('enabled')
            : context.l10n.t('disabled'),
        valueColor: detail.enabled
            ? theme.colorScheme.primary
            : theme.colorScheme.error,
      ),
      if (detail.codePath.isNotEmpty)
        AppDetailSummaryField(
          label: context.l10n.t('harmonyCodePath'),
          value: detail.codePath,
          copyable: true,
          maxLines: 4,
        ),
      if (detail.fingerprint.isNotEmpty)
        AppDetailSummaryField(
          label: context.l10n.t('harmonyFingerprint'),
          value: detail.fingerprint,
          copyable: true,
          maxLines: 4,
        ),
    ];

    final data = AppDetailViewData(
      name: widget.package.displayName,
      version: detail.versionName.isNotEmpty
          ? detail.versionName
          : _harmonyValue(detail.versionCode),
      logo: AppDetailLogoData(
        image: iconPath != null && File(iconPath).existsSync()
            ? FileImage(File(iconPath))
            : null,
        fallbackImage: const AssetImage(AppIcons.harmonyDefaultAppIcon),
      ),
      badges: [
        const AppDetailSummaryBadge(label: 'HarmonyOS'),
        if (detail.cpuAbi.isNotEmpty)
          AppDetailSummaryBadge(label: detail.cpuAbi),
        if (detail.provisionType.isNotEmpty)
          AppDetailSummaryBadge(
            label: detail.provisionType.toUpperCase(),
            tone: detail.provisionType.toLowerCase() == 'debug'
                ? AppDetailBadgeTone.warning
                : AppDetailBadgeTone.success,
          ),
      ],
      fields: fields,
      tabs: tabs,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(CupertinoIcons.arrow_left),
                tooltip: context.l10n.t('back'),
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 12),
              Text(
                context.l10n.t('harmonyAppAnalysis'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text('/', style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.package.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: _refreshing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.arrow_2_circlepath),
                tooltip: context.l10n.t('refreshSingleApp'),
                onPressed: _refreshing ? null : _refresh,
              ),
            ],
          ),
        ),
        Expanded(
          child: AppDetailView(
            data: data,
            summaryBackground: theme.colorScheme.surfaceContainerLowest
                .withValues(alpha: 0.55),
            copyTooltip: context.l10n.t('copy'),
            onCopied: (field) => _showSnack(
              context,
              context.l10n
                  .t('harmonyFieldCopied')
                  .replaceAll('{field}', field.label),
            ),
            tabViews: [
              _HarmonyModuleList(modules: modules),
              _HarmonyComponentList(components: abilities),
              _HarmonyComponentList(components: extensions),
              _HarmonyPermissionList(permissions: permissions),
              _HarmonyMetadataList(metadata: metadata),
            ],
          ),
        ),
      ],
    );
  }
}

class _HarmonyModuleList extends StatelessWidget {
  const _HarmonyModuleList({required this.modules});

  final List<HarmonyModuleDetail> modules;

  @override
  Widget build(BuildContext context) {
    return _HarmonyAnalysisList(
      emptyText: context.l10n.t('harmonyNoModules'),
      children: [
        for (final module in modules)
          ListTile(
            leading: const Icon(CupertinoIcons.cube_box),
            title: Text(_harmonyValue(module.name)),
            subtitle: Text(
              [
                if (module.mainElementName.isNotEmpty)
                  '${context.l10n.t('harmonyMainElement')}: ${module.mainElementName}',
                if (module.deviceTypes.isNotEmpty)
                  '${context.l10n.t('harmonyDeviceTypes')}: ${module.deviceTypes.join(', ')}',
                if (module.nativeLibraries.isNotEmpty)
                  '${context.l10n.t('harmonyNativeLibraries')}: ${module.nativeLibraries.join(', ')}',
                if (module.hapPath.isNotEmpty) module.hapPath,
              ].join('\n'),
            ),
            trailing: Text(
              '${module.abilities.length} / ${module.extensions.length}',
            ),
          ),
      ],
    );
  }
}

class _HarmonyComponentList extends StatelessWidget {
  const _HarmonyComponentList({required this.components});

  final List<HarmonyComponentDetail> components;

  @override
  Widget build(BuildContext context) {
    return _HarmonyAnalysisList(
      emptyText: context.l10n.t('harmonyNoComponents'),
      children: [
        for (final component in components)
          ListTile(
            leading: Icon(
              component.visible ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
            ),
            title: Text(_harmonyValue(component.name)),
            subtitle: Text(
              [
                if (component.moduleName.isNotEmpty)
                  '${context.l10n.t('harmonyModule')}: ${component.moduleName}',
                if (component.sourceEntry.isNotEmpty) component.sourceEntry,
                if (component.process.isNotEmpty)
                  '${context.l10n.t('harmonyProcess')}: ${component.process}',
                if (component.actions.isNotEmpty)
                  '${context.l10n.t('harmonyActions')}: ${component.actions.join(', ')}',
                if (component.entities.isNotEmpty)
                  '${context.l10n.t('harmonyEntities')}: ${component.entities.join(', ')}',
                if (component.permissions.isNotEmpty)
                  '${context.l10n.t('permissions')}: ${component.permissions.join(', ')}',
              ].join('\n'),
            ),
            trailing: component.type.isEmpty ? null : Text(component.type),
          ),
      ],
    );
  }
}

class _HarmonyPermissionList extends StatelessWidget {
  const _HarmonyPermissionList({required this.permissions});

  final List<HarmonyPermissionDetail> permissions;

  @override
  Widget build(BuildContext context) {
    return _HarmonyAnalysisList(
      emptyText: context.l10n.t('noPermissions'),
      children: [
        for (final permission in permissions)
          ListTile(
            leading: const Icon(CupertinoIcons.shield),
            title: Text(permission.name),
            subtitle: Text(
              [
                if (permission.moduleName.isNotEmpty)
                  '${context.l10n.t('harmonyModule')}: ${permission.moduleName}',
                if (permission.reason.isNotEmpty) permission.reason,
                if (permission.when.isNotEmpty)
                  '${context.l10n.t('harmonyUsedWhen')}: ${permission.when}',
              ].join('\n'),
            ),
          ),
      ],
    );
  }
}

class _HarmonyMetadataList extends StatelessWidget {
  const _HarmonyMetadataList({required this.metadata});

  final Map<String, String> metadata;

  @override
  Widget build(BuildContext context) {
    return _HarmonyAnalysisList(
      emptyText: context.l10n.t('harmonyNoMetadata'),
      children: [
        for (final entry in metadata.entries)
          ListTile(
            leading: const Icon(CupertinoIcons.tag),
            title: Text(entry.key),
            subtitle: Text(_harmonyValue(entry.value)),
          ),
      ],
    );
  }
}

class _HarmonyAnalysisList extends StatelessWidget {
  const _HarmonyAnalysisList({required this.emptyText, required this.children});

  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return Center(child: Text(emptyText));
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: children.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) => children[index],
    );
  }
}

String _harmonyValue(Object value) {
  final text = value.toString().trim();
  return text.isEmpty || text == '0' ? '-' : text;
}

String _joinedHarmonyValue(List<String> values) {
  final text = values.where((item) => item.isNotEmpty).join(' / ');
  return text.isEmpty ? '-' : text;
}

String _formatHarmonyTime(int milliseconds) {
  if (milliseconds <= 0) return '-';
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String digits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${digits(date.month)}-${digits(date.day)} '
      '${digits(date.hour)}:${digits(date.minute)}:${digits(date.second)}';
}
