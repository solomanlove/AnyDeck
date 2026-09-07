import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/adb_device.dart';
import '../../core/ios/ios_mirror_service.dart';
import '../widgets/dashboard_snack.dart';
import 'ios_tool_widgets.dart';

/// 通过 AFC/fsync 访问开启 File Sharing 的 iOS App container。
class IosFilesTab extends ConsumerStatefulWidget {
  const IosFilesTab({super.key, required this.device});

  final AdbDevice device;

  @override
  ConsumerState<IosFilesTab> createState() => _IosFilesTabState();
}

class _IosFilesTabState extends ConsumerState<IosFilesTab> {
  final _bundleController = TextEditingController();
  final _remoteController = TextEditingController(text: '/');
  bool _loading = false;
  String _output = '';

  @override
  void dispose() {
    _bundleController.dispose();
    _remoteController.dispose();
    super.dispose();
  }

  bool _validate() {
    if (_bundleController.text.trim().isNotEmpty &&
        _remoteController.text.trim().isNotEmpty) {
      return true;
    }
    DashboardSnack.show(
      context,
      context.l10n.t('iosFileContainerHint'),
      isError: true,
    );
    return false;
  }

  Future<void> _list() async {
    if (_loading || !_validate()) return;
    setState(() => _loading = true);
    final result = await ref
        .read(iosCommandServiceProvider)
        .listFiles(
          widget.device.id,
          bundleId: _bundleController.text.trim(),
          remotePath: _remoteController.text.trim(),
        );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _output = result.isSuccess ? result.stdout : result.message;
    });
  }

  Future<void> _push() async {
    if (_loading || !_validate()) return;
    final file = await openFile();
    if (file == null || !mounted) return;
    setState(() => _loading = true);
    final result = await ref
        .read(iosCommandServiceProvider)
        .pushFile(
          widget.device.id,
          bundleId: _bundleController.text.trim(),
          localPath: file.path,
          remotePath: _remoteController.text.trim(),
        );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _output = result.isSuccess ? result.stdout : result.message;
    });
    DashboardSnack.show(
      context,
      result.isSuccess
          ? context.l10n.t('iosFilePushSuccess')
          : context.l10n
                .t('iosCommandFailed')
                .replaceAll('{error}', result.message),
      isError: !result.isSuccess,
    );
  }

  Future<void> _pull() async {
    if (_loading || !_validate()) return;
    final remotePath = _remoteController.text.trim();
    final suggestedName = remotePath.split('/').lastOrNull ?? 'ios_file';
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null || !mounted) return;
    setState(() => _loading = true);
    final result = await ref
        .read(iosCommandServiceProvider)
        .pullFile(
          widget.device.id,
          bundleId: _bundleController.text.trim(),
          remotePath: remotePath,
          localPath: location.path,
        );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _output = result.isSuccess ? result.stdout : result.message;
    });
    DashboardSnack.show(
      context,
      result.isSuccess
          ? context.l10n.t('iosFilePullSuccess')
          : context.l10n
                .t('iosCommandFailed')
                .replaceAll('{error}', result.message),
      isError: !result.isSuccess,
    );
  }

  @override
  Widget build(BuildContext context) {
    return IosToolScaffold(
      title: context.l10n.t('files'),
      description: context.l10n.t('iosFileContainerHint'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _bundleController,
            decoration: InputDecoration(
              labelText: context.l10n.t('iosBundleId'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _remoteController,
            decoration: InputDecoration(
              labelText: context.l10n.t('iosRemotePath'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _loading ? null : _list,
                icon: const Icon(Icons.folder_open),
                label: Text(context.l10n.t('iosListFiles')),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _push,
                icon: const Icon(Icons.upload_file),
                label: Text(context.l10n.t('push')),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _pull,
                icon: const Icon(Icons.download),
                label: Text(context.l10n.t('pull')),
              ),
              if (_loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          IosCommandOutput(output: _output),
        ],
      ),
    );
  }
}
