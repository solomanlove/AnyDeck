import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/app_toast.dart';
import '../../../core/emulator/emulator_ide_providers.dart';
import '../../../core/emulator/harmony/deveco_emulator_providers.dart';
import '../../../core/environment/connection_environment_service.dart';
import '../../../core/providers/modules/service_providers.dart';
import 'emulator_platform_tabs.dart';

/// 展示指定 [platform] 的模拟器空态和 IDE 安装指引。
///
/// 用于无本地模拟器的页面，传入 [isScanning] 表示列表尚在扫描。
class EmulatorEmptyState extends ConsumerStatefulWidget {
  const EmulatorEmptyState({
    super.key,
    required this.platform,
    this.isScanning = false,
  });

  final EmulatorPlatform platform;
  final bool isScanning;

  @override
  ConsumerState<EmulatorEmptyState> createState() => _EmulatorEmptyStateState();
}

class _EmulatorEmptyStateState extends ConsumerState<EmulatorEmptyState> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final guide = _guides[widget.platform]!;

    if (widget.platform == EmulatorPlatform.ios &&
        ref.watch(emulatorIdeServiceProvider).platform !=
            TargetPlatform.macOS) {
      return _buildMessage(
        context,
        title: l10n.t('iosEmulatorRequiresMac'),
        message: l10n.t('iosEmulatorRequiresMacHint'),
      );
    }

    if (widget.isScanning) {
      return _buildProgress(l10n.t(guide.scanningKey));
    }

    // 开发工具的安装状态独立于真机连接和本地模拟器列表。
    final supportsDetection =
        widget.platform != EmulatorPlatform.harmony ||
        ref.watch(devecoEmulatorServiceProvider).supportsStudioDetection;
    final studio = supportsDetection ? ref.watch(guide.appPathProvider) : null;
    if (studio?.isLoading == true) {
      return _buildProgress(_translateIde('emulatorIdeChecking', guide));
    }

    final appPath = studio?.value;
    return _buildMessage(
      context,
      title: supportsDetection && appPath == null
          ? _translateIde('emulatorIdeNotDetected', guide)
          : l10n.t(guide.noEmulatorsKey),
      message: l10n.t(appPath == null ? guide.installKey : guide.configureKey),
      action: FilledButton.icon(
        icon: Icon(appPath == null ? Icons.download : Icons.launch, size: 16),
        label: Text(
          _translateIde(
            appPath == null ? 'emulatorIdeDownload' : 'emulatorIdeOpen',
            guide,
          ),
        ),
        onPressed: _opening ? null : () => _open(guide, appPath),
      ),
    );
  }

  Widget _buildMessage(
    BuildContext context, {
    required String title,
    required String message,
    Widget? action,
  }) {
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
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 20), action],
            ],
          ),
        ),
      ),
    );
  }

  String _translateIde(String key, _EmulatorIdeGuide guide) =>
      context.l10n.t(key).replaceAll('{ide}', guide.name);

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
  Future<void> _open(_EmulatorIdeGuide guide, String? appPath) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final opened = await _openGuide(guide, appPath);
      if (!mounted || opened) return;
      AppToast.show(
        context,
        _translateIde(
          appPath == null
              ? 'emulatorIdeDownloadOpenFailed'
              : 'emulatorIdeOpenFailed',
          guide,
        ),
        isError: true,
      );
      if (appPath != null) ref.invalidate(guide.appPathProvider);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<bool> _openGuide(_EmulatorIdeGuide guide, String? appPath) {
    if (appPath == null) {
      return ref
          .read(hostPlatformServiceProvider)
          .openWebUri(Uri.parse(guide.downloadUrl));
    }
    if (widget.platform == EmulatorPlatform.harmony) {
      return ref
          .read(devecoEmulatorServiceProvider)
          .openDevEcoStudio(appPath: appPath);
    }
    return ref.read(emulatorIdeServiceProvider).open(appPath);
  }
}

/// 各平台的指引用词、下载页和安装探测入口。
typedef _EmulatorIdeGuide = ({
  String name,
  String scanningKey,
  String noEmulatorsKey,
  String installKey,
  String configureKey,
  String downloadUrl,
  FutureProvider<String?> appPathProvider,
});

final _guides = <EmulatorPlatform, _EmulatorIdeGuide>{
  EmulatorPlatform.android: (
    name: 'Android Studio',
    scanningKey: 'scanningEmulators',
    noEmulatorsKey: 'androidNoLocalEmulators',
    installKey: 'androidEmulatorInstallHint',
    configureKey: 'androidEmulatorConfigureHint',
    downloadUrl: 'https://developer.android.com/studio',
    appPathProvider: androidStudioAppPathProvider,
  ),
  EmulatorPlatform.harmony: (
    name: 'DevEco Studio',
    scanningKey: 'devecoScanningEmulators',
    noEmulatorsKey: 'devecoNoLocalEmulators',
    installKey: 'devecoInstallStudioHint',
    configureKey: 'devecoConfigureEmulatorHint',
    downloadUrl: ConnectionEnvironmentService.devecoStudioDownloadUrl,
    appPathProvider: devecoStudioAppPathProvider,
  ),
  EmulatorPlatform.ios: (
    name: 'Xcode',
    scanningKey: 'xcodeScanningSimulators',
    noEmulatorsKey: 'iosNoLocalSimulators',
    installKey: 'iosSimulatorInstallHint',
    configureKey: 'iosSimulatorConfigureHint',
    downloadUrl: 'https://apps.apple.com/us/app/xcode/id497799835',
    appPathProvider: xcodeAppPathProvider,
  ),
};
