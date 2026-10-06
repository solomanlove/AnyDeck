import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/widget/dashboard_tab_layout.dart';
import '../../core/adb/adb_device.dart';
import '../../core/ios/ios_process_info.dart';
import '../../core/ios/ios_process_service.dart';
import '../../core/providers/app_providers.dart';
import '../widgets/dashboard_snack.dart';
import 'controller/ios_processes_controller.dart';
import 'model/ios_processes_filter.dart';
import 'widgets/ios_process_tile.dart';
import 'widgets/ios_processes_table.dart';
import 'widgets/ios_processes_toolbar.dart';

/// iOS 全进程管理入口；离页、断线或切换设备使旧会话失去监听并取消。
class IosProcessesTab extends ConsumerWidget {
  const IosProcessesTab({super.key, required this.device});
  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(deviceOnlineProvider(device.id))) {
      return Center(child: Text(context.l10n.t('offlineProcessWarning')));
    }
    return _IosProcessesView(key: ValueKey(device.id), udid: device.id);
  }
}

/// 持有输入框与筛选状态，设备操作和计时器交给 autoDispose Notifier。
class _IosProcessesView extends ConsumerStatefulWidget {
  const _IosProcessesView({super.key, required this.udid});
  final String udid;
  @override
  ConsumerState<_IosProcessesView> createState() => _IosProcessesViewState();
}

class _IosProcessesViewState extends ConsumerState<_IosProcessesView> {
  final _search = TextEditingController();
  IosProcessFilter _category = IosProcessFilter.all;
  IosProcessSort _sort = IosProcessSort.name;
  bool _ascending = true;
  bool _onlyApps = false;
  bool _confirming = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(iosProcessesProvider(widget.udid));
    final controller = ref.read(iosProcessesProvider(widget.udid).notifier);
    final items = filterIosProcesses(
      state.items,
      category: _category,
      onlyApps: _onlyApps,
      query: _search.text,
      sort: _sort,
      ascending: _ascending,
    );
    return DashboardTabLayout(
      toolbar: IosProcessesToolbar(
        controller: _search,
        category: _category,
        onlyApps: _onlyApps,
        autoRefresh: state.autoRefresh,
        busy: state.busy || _confirming,
        onQuery: (_) => setState(() {}),
        onCategory: (value) => setState(() => _category = value),
        onOnlyApps: (value) => setState(() => _onlyApps = value),
        onAutoRefresh: controller.setAutoRefresh,
        onRefresh: () => controller.refresh(refreshApps: true),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.t('iosProcessMetricsHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (state.metadataError != null)
            _warning(context.l10n.t('iosProcessMetadataError')),
          if (state.error != null)
            _warning(
              context.l10n
                  .t('iosProcessStale')
                  .replaceAll('{error}', state.error!),
            ),
          SizedBox(
            height: 4,
            child: state.busy ? const LinearProgressIndicator() : null,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: IosProcessesTable(
              items: items,
              total: state.items.length,
              sort: _sort,
              ascending: _ascending,
              onSort: (value) => setState(() {
                _ascending = _sort == value ? !_ascending : true;
                _sort = value;
              }),
              onMenu: _menu,
            ),
          ),
        ],
      ),
    );
  }

  Widget _warning(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  Future<void> _menu(IosProcessInfo item, Offset position) async {
    final state = ref.read(iosProcessesProvider(widget.udid));
    final bundle =
        item.bundleId ?? (item.isExtension ? null : item.app?.bundleId);
    final entries = <IosProcessAction, String>{
      IosProcessAction.name: 'copyProcessName',
      IosProcessAction.pid: 'iosProcessCopyPid',
      if (bundle != null) IosProcessAction.bundle: 'iosProcessCopyBundle',
      if (item.isExtension && item.app != null)
        IosProcessAction.hostBundle: 'iosProcessCopyHost',
      if (item.executablePath != null)
        IosProcessAction.path: 'iosProcessCopyPath',
      IosProcessAction.details: 'iosProcessDetails',
      IosProcessAction.kill: 'iosKillProcess',
    };
    final action = await showMenu<IosProcessAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: entries.entries
          .map(
            (entry) => PopupMenuItem(
              value: entry.key,
              enabled:
                  entry.key != IosProcessAction.kill ||
                  (!state.busy && !_confirming),
              child: Text(context.l10n.t(entry.value)),
            ),
          )
          .toList(),
    );
    if (!mounted || action == null) return;
    if (action == IosProcessAction.kill) {
      await _kill(item);
      return;
    }
    if (action == IosProcessAction.details) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.t('iosProcessDetails')),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(child: IosProcessTile(process: item)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.t('close')),
            ),
          ],
        ),
      );
      return;
    }
    final value = switch (action) {
      IosProcessAction.name => item.name,
      IosProcessAction.pid => '${item.pid}',
      IosProcessAction.bundle => bundle,
      IosProcessAction.hostBundle => item.app?.bundleId,
      IosProcessAction.path => item.executablePath,
      _ => null,
    };
    if (value == null) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) DashboardSnack.show(context, context.l10n.t('copySuccess'));
  }

  Future<void> _kill(IosProcessInfo item) async {
    final provider = iosProcessesProvider(widget.udid);
    final state = ref.read(provider);
    if (_confirming || state.busy) return;
    final controller = ref.read(provider.notifier);
    // 确认期间暂停轮询；退出弹窗后恢复用户原来的设置。
    controller.setAutoRefresh(false);
    setState(() => _confirming = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.t('iosKillProcess')),
          content: Text(
            context.l10n
                .t('killProcessConfirm')
                .replaceAll('{name}', item.displayName)
                .replaceAll('{pid}', '${item.pid}'),
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
      await controller.kill(item);
    } catch (error) {
      if (!mounted) return;
      DashboardSnack.show(
        context,
        error is IosProcessChanged
            ? context.l10n.t('iosProcessChanged')
            : context.l10n
                  .t('iosCommandFailed')
                  .replaceAll('{error}', '$error'),
        isError: true,
      );
    } finally {
      if (mounted) {
        controller.setAutoRefresh(state.autoRefresh);
        setState(() => _confirming = false);
      }
    }
  }
}
