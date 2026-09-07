import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/adb_device.dart';
import '../../core/ios/ios_app_info.dart';
import '../../core/ios/ios_mirror_service.dart';
import '../widgets/dashboard_snack.dart';

/// 通过 installation_proxy 管理 iOS 应用。
class IosAppsTab extends ConsumerStatefulWidget {
  const IosAppsTab({super.key, required this.device});

  final AdbDevice device;

  @override
  ConsumerState<IosAppsTab> createState() => _IosAppsTabState();
}

class _IosAppsTabState extends ConsumerState<IosAppsTab> {
  List<IosAppInfo> _apps = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await ref
          .read(iosCommandServiceProvider)
          .listApps(widget.device.id);
      if (mounted) setState(() => _apps = apps);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _install() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'IPA', extensions: ['ipa']),
      ],
    );
    if (file == null || !mounted) return;
    setState(() => _loading = true);
    final result = await ref
        .read(iosCommandServiceProvider)
        .installApp(widget.device.id, file.path);
    if (!mounted) return;
    setState(() => _loading = false);
    DashboardSnack.show(
      context,
      result.isSuccess
          ? context.l10n.t('iosInstallSuccess')
          : context.l10n
                .t('iosCommandFailed')
                .replaceAll('{error}', result.message),
      isError: !result.isSuccess,
    );
    if (result.isSuccess) await _refresh();
  }

  Future<void> _uninstall(IosAppInfo app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('uninstall')),
        content: Text(
          context.l10n
              .t('uninstallPackage')
              .replaceAll('{package}', app.bundleId),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.t('confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    final result = await ref
        .read(iosCommandServiceProvider)
        .uninstallApp(widget.device.id, app.bundleId);
    if (!mounted) return;
    setState(() => _loading = false);
    DashboardSnack.show(
      context,
      result.isSuccess
          ? context.l10n.t('iosUninstallSuccess')
          : context.l10n
                .t('iosCommandFailed')
                .replaceAll('{error}', result.message),
      isError: !result.isSuccess,
    );
    if (result.isSuccess) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.t('iosAppList'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _loading ? null : _install,
                icon: const Icon(Icons.install_mobile),
                label: Text(context.l10n.t('iosInstallIpa')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.t('refresh')),
              ),
              if (_loading) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (_apps.isEmpty) {
      return _loading
          ? const SizedBox.shrink()
          : Center(child: Text(context.l10n.t('noPackages')));
    }
    return ListView.builder(
      itemCount: _apps.length,
      itemBuilder: (context, index) {
        final app = _apps[index];
        return Card(
          child: ListTile(
            leading: Icon(app.system ? Icons.settings : Icons.apps),
            title: Text(app.name),
            subtitle: Text(
              '${app.bundleId}\n${context.l10n.t('iosAppVersion')}: ${app.version ?? '-'}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: context.l10n.t('uninstall'),
              onPressed: _loading || app.system ? null : () => _uninstall(app),
              icon: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        );
      },
    );
  }
}
