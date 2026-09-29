import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/widget/dashboard_tab_layout.dart';
import '../../core/adb/adb_device.dart';
import '../../core/adb/adb_result.dart';
import '../../core/ios/ios_app_info.dart';
import '../../core/ios/ios_mirror_service.dart';
import '../widgets/dashboard_snack.dart';
import 'controller/ios_apps_controller.dart';
import 'model/ios_apps_filter.dart';
import 'widgets/ios_apps_table.dart';
import 'widgets/ios_apps_toolbar.dart';

/// 通过 installation_proxy 管理 iOS 应用，沿用 Android 应用页的工具栏和表格布局。
class IosAppsTab extends ConsumerStatefulWidget {
  const IosAppsTab({super.key, required this.device});

  final AdbDevice device;

  @override
  ConsumerState<IosAppsTab> createState() => _IosAppsTabState();
}

class _IosAppsTabState extends ConsumerState<IosAppsTab> {
  final _filterController = TextEditingController();
  IosAppFilter _category = IosAppFilter.user;
  bool _busy = false;
  int _deviceGeneration = 0;

  @override
  void didUpdateWidget(covariant IosAppsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _deviceGeneration++;
      _busy = false;
      _filterController.clear();
      _category = IosAppFilter.user;
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(iosAppsProvider(widget.device.id));

  /// 文件选择、确认弹窗和命令都绑定发起时的设备，避免切换后操作另一台手机。
  Future<void> _install() async {
    if (_busy) return;
    final generation = _deviceGeneration;
    final udid = widget.device.id;
    setState(() => _busy = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'IPA', extensions: ['ipa']),
        ],
      );
      if (file == null || !mounted || generation != _deviceGeneration) return;
      final result = await ref
          .read(iosCommandServiceProvider)
          .installApp(udid, file.path);
      if (!mounted || generation != _deviceGeneration) return;
      _showResult(result, 'iosInstallSuccess');
      if (result.isSuccess) _refresh();
    } catch (error) {
      if (mounted && generation == _deviceGeneration) _showError(error);
    } finally {
      if (mounted && generation == _deviceGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _uninstall(IosAppInfo app) async {
    if (_busy || app.system) return;
    final generation = _deviceGeneration;
    final udid = widget.device.id;
    setState(() => _busy = true);
    try {
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
      if (confirmed != true || !mounted || generation != _deviceGeneration) {
        return;
      }
      final result = await ref
          .read(iosCommandServiceProvider)
          .uninstallApp(udid, app.bundleId);
      if (!mounted || generation != _deviceGeneration) return;
      _showResult(result, 'iosUninstallSuccess');
      if (result.isSuccess) _refresh();
    } catch (error) {
      if (mounted && generation == _deviceGeneration) _showError(error);
    } finally {
      if (mounted && generation == _deviceGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(Object error) => DashboardSnack.show(
    context,
    context.l10n.t('iosCommandFailed').replaceAll('{error}', '$error'),
    isError: true,
  );

  void _showResult(AdbResult result, String successKey) => DashboardSnack.show(
    context,
    result.isSuccess
        ? context.l10n.t(successKey)
        : context.l10n
              .t('iosCommandFailed')
              .replaceAll('{error}', result.message),
    isError: !result.isSuccess,
  );

  Future<void> _toggleFavorite(IosAppInfo app) async {
    try {
      await ref.read(iosAppFavoritesProvider.notifier).toggle(app.bundleId);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = ref.watch(iosAppsProvider(widget.device.id));
    final favorites = ref.watch(iosAppFavoritesProvider);
    final favoriteIds = favorites.value ?? const <String>{};
    final busy = _busy || apps.isLoading;
    return DashboardTabLayout(
      toolbar: IosAppsToolbar(
        controller: _filterController,
        category: _category,
        onQueryChanged: (_) => setState(() {}),
        onCategoryChanged: (category) => setState(() => _category = category),
        busy: busy,
        onRefresh: _refresh,
        onInstall: _install,
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: apps.when(
              skipLoadingOnRefresh: false,
              data: (items) => IosAppsTable(
                key: ValueKey(widget.device.id),
                apps: filterIosApps(
                  items,
                  category: _category,
                  query: _filterController.text,
                  favorites: favoriteIds,
                ),
                totalCount: items.length,
                favorites: favoriteIds,
                onFavorite: favorites.hasValue ? _toggleFavorite : null,
                onUninstall: busy ? null : _uninstall,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  context.l10n
                      .t('iosCommandFailed')
                      .replaceAll('{error}', '$error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
