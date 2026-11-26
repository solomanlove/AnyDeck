import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/app_toast.dart';
import '../../../core/emulator/harmony/deveco_emulator_providers.dart';
import '../../../core/environment/connection_environment_service.dart';
import '../../../core/providers/modules/service_providers.dart';

/// 展示 HarmonyOS 模拟器列表为空时的扫描进度与安装指引。
///
/// 用于无本地模拟器的页面，传入 [isScanning] 表示列表尚在扫描。
class DevecoEmulatorEmptyState extends ConsumerStatefulWidget {
  const DevecoEmulatorEmptyState({super.key, required this.isScanning});

  final bool isScanning;

  @override
  ConsumerState<DevecoEmulatorEmptyState> createState() =>
      _DevecoEmulatorEmptyStateState();
}

class _DevecoEmulatorEmptyStateState
    extends ConsumerState<DevecoEmulatorEmptyState> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isScanning) {
      return _buildProgress(context.l10n.t('devecoScanningEmulators'));
    }

    // 真机连接使用的 HDC 可独立安装，空态以 DevEco Studio 应用包为准。
    final supportsDetection = ref
        .watch(devecoEmulatorServiceProvider)
        .supportsStudioDetection;
    final studio = supportsDetection
        ? ref.watch(devecoStudioAppPathProvider)
        : null;
    if (studio?.isLoading == true) {
      return _buildProgress(context.l10n.t('devecoCheckingStudio'));
    }

    final appPath = studio?.value;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.devices,
                size: 52,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.t(
                  supportsDetection && appPath == null
                      ? 'devecoStudioNotDetected'
                      : 'devecoNoLocalEmulators',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.t(
                  appPath == null
                      ? 'devecoInstallStudioHint'
                      : 'devecoConfigureEmulatorHint',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: Icon(
                  appPath == null ? Icons.download : Icons.launch,
                  size: 16,
                ),
                label: Text(
                  l10n.t(
                    appPath == null ? 'harmonyOpenDevEco' : 'devecoOpenStudio',
                  ),
                ),
                onPressed: _opening ? null : () => _open(appPath),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgress(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  /// 禁止重复打开，应用路径可能失效时重新检查安装状态。
  Future<void> _open(String? appPath) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final opened = appPath == null
          ? await ref
                .read(hostPlatformServiceProvider)
                .openWebUri(
                  Uri.parse(
                    ConnectionEnvironmentService.devecoStudioDownloadUrl,
                  ),
                )
          : await ref
                .read(devecoEmulatorServiceProvider)
                .openDevEcoStudio(appPath: appPath);
      if (!mounted || opened) return;
      AppToast.show(
        context,
        context.l10n.t(
          appPath == null
              ? 'devecoDownloadOpenFailed'
              : 'devecoStudioOpenFailed',
        ),
        isError: true,
      );
      if (appPath != null) ref.invalidate(devecoStudioAppPathProvider);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
