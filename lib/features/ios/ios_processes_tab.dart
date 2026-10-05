import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/adb_device.dart';
import '../../core/ios/ios_mirror_service.dart';
import '../../core/ios/ios_process_info.dart';
import '../widgets/dashboard_snack.dart';
import 'widgets/ios_process_tile.dart';

/// 通过 go-ios instruments 进程服务查看和结束 iOS App 进程。
class IosProcessesTab extends ConsumerStatefulWidget {
  const IosProcessesTab({super.key, required this.device});

  final AdbDevice device;

  @override
  ConsumerState<IosProcessesTab> createState() => _IosProcessesTabState();
}

class _IosProcessesTabState extends ConsumerState<IosProcessesTab> {
  List<IosProcessInfo> _processes = const [];
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant IosProcessesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id == widget.device.id) return;
    // 切换设备后旧进程及其补充信息不得写入新设备页面。
    _processes = const [];
    _loading = false;
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final processes = await ref
          .read(iosCommandServiceProvider)
          .listProcesses(widget.device.id);
      if (mounted && requestId == _requestId) {
        setState(() => _processes = processes);
      }
    } catch (error) {
      if (mounted && requestId == _requestId) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _kill(IosProcessInfo process) async {
    final udid = widget.device.id;
    final requestId = _requestId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('iosKillProcess')),
        content: Text(
          context.l10n
              .t('killProcessConfirm')
              .replaceAll('{name}', process.displayName)
              .replaceAll('{pid}', '${process.pid}'),
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
    if (confirmed != true || !mounted || requestId != _requestId) return;
    setState(() => _loading = true);
    final result = await ref
        .read(iosCommandServiceProvider)
        .killProcess(udid, process.pid);
    if (!mounted || requestId != _requestId) return;
    setState(() => _loading = false);
    if (!result.isSuccess) {
      DashboardSnack.show(
        context,
        context.l10n
            .t('iosCommandFailed')
            .replaceAll('{error}', result.message),
        isError: true,
      );
      return;
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.t('iosProcesses'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.t('refresh')),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          const SizedBox(height: 8),
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
    if (_processes.isEmpty) {
      return _loading
          ? const SizedBox.shrink()
          : Center(child: Text(context.l10n.t('noMatchingProcesses')));
    }
    return ListView.builder(
      itemCount: _processes.length,
      itemBuilder: (context, index) {
        final process = _processes[index];
        return IosProcessTile(
          process: process,
          onKill: _loading ? null : () => _kill(process),
        );
      },
    );
  }
}
