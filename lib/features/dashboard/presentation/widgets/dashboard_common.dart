part of '../dashboard_screen.dart';

class _RotatingWidget extends StatefulWidget {
  const _RotatingWidget({required this.child});

  final Widget child;

  @override
  State<_RotatingWidget> createState() => _RotatingWidgetState();
}

class _RotatingWidgetState extends State<_RotatingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(turns: _controller, child: widget.child);
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.animateIcon = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool animateIcon;

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Icon(
      icon,
      size: 36,
      color: Theme.of(context).colorScheme.primary,
    );
    if (animateIcon) {
      iconWidget = _RotatingWidget(child: iconWidget);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 等待 adb 命令完成，并通过 SnackBar 展示统一结果。
Future<void> _runAdbAction(
  BuildContext context,
  WidgetRef ref,
  Future<AdbResult> future,
) async {
  final result = await future;
  await _syncAdbStateAfterResult(ref, result);
  if (!context.mounted) {
    return;
  }
  _showSnack(context, result.message, isError: !result.isSuccess);
}

Future<void> _syncAdbStateAfterResult(WidgetRef ref, AdbResult result) async {
  await ref.read(deviceRegistryProvider.notifier).syncAfterAdbResult(result);
}

/// 主动刷新 adb 设备列表，避免仅重建 StreamProvider 时 UI 无明显反馈。
Future<void> _refreshDevices(BuildContext context, WidgetRef ref) async {
  final result = await ref
      .read(deviceRegistryProvider.notifier)
      .refreshDevices();
  if (!context.mounted) {
    return;
  }
  _showSnack(
    context,
    result.isSuccess
        ? context.l10n.t('devicesRefreshed')
        : '${context.l10n.t('adbUnavailable')}: ${result.message}',
    isError: !result.isSuccess,
  );
}

/// 重启 ADB server，并在完成后刷新设备流。
Future<void> _restartAdbServer(BuildContext context, WidgetRef ref) async {
  _showSnack(context, context.l10n.t('restartingAdb'));
  final result = await ref.read(deviceRegistryProvider.notifier).restartAdb();
  if (!context.mounted) {
    return;
  }
  _showSnack(
    context,
    result.isSuccess
        ? context.l10n.t('restartAdbSuccess')
        : '${context.l10n.t('restartAdbFailed')}: ${result.message}',
    isError: !result.isSuccess,
  );
}

/// 展示 TCP/IP 连接弹窗，供左侧导航和设备列表共同复用。
Future<void> _showConnectDeviceDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final controller = TextEditingController(text: '192.168.1.10:5555');
  final address = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(context.l10n.t('connectDevice')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: context.l10n.t('ipAddress')),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton.icon(
            icon: const Icon(CupertinoIcons.link),
            label: Text(context.l10n.t('connect')),
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      );
    },
  );
  controller.dispose();

  if (address == null || address.trim().isEmpty || !context.mounted) {
    return;
  }

  await _runAdbAction(
    context,
    ref,
    ref.read(deviceRegistryProvider.notifier).connectDevice(address.trim()),
  );
}

/// 执行 adb 命令，并在弹窗中展示完整输出。
Future<void> _showAdbResult(
  BuildContext context,
  WidgetRef ref,
  Future<AdbResult> future,
) async {
  final result = await future;
  await _syncAdbStateAfterResult(ref, result);
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          result.isSuccess ? context.l10n.t('result') : context.l10n.t('error'),
        ),
        content: SelectableText(result.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.t('close')),
          ),
        ],
      );
    },
  );
}

/// 展示确认弹窗，用户直接关闭时默认返回 false。
Future<bool> _confirm(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(context.l10n.t('confirm')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.t('confirm')),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// 展示应用级短消息。
void _showSnack(BuildContext context, String message, {bool isError = false}) {
  DashboardSnack.show(context, message, isError: isError);
}

/// 拼接远程目录路径和文件名，不参与宿主机路径处理。
String _joinRemotePath(String base, String name) {
  final normalized = base.endsWith('/') ? base : '$base/';
  return '$normalized$name';
}

/// 根据解析出的远程文件类型选择图标。
IconData _fileIcon(RemoteFile file) {
  return switch (file.type) {
    RemoteFileType.folder => CupertinoIcons.folder,
    RemoteFileType.link => CupertinoIcons.link,
    RemoteFileType.file => CupertinoIcons.doc,
  };
}

void _showAppDetailsDialog(
  BuildContext context,
  WidgetRef ref,
  String deviceId,
  AdbPackage package,
) {
  showDialog(
    context: context,
    builder: (context) {
      return _AppDetailsDialog(deviceId: deviceId, package: package);
    },
  );
}

Future<void> _openLocalTerminal(BuildContext context, WidgetRef ref) async {
  try {
    final adbPath = ref.read(adbServiceProvider).executable;
    String dirPath = Directory.current.path;
    if (adbPath != 'adb') {
      final adbFile = File(adbPath);
      if (adbFile.existsSync()) {
        dirPath = adbFile.parent.path;
      }
    }

    final opened = await ref
        .read(hostPlatformServiceProvider)
        .openTerminal(dirPath);
    if (!opened) {
      throw Exception('Open terminal command failed');
    }
    if (context.mounted) {
      _showSnack(context, '${context.l10n.t('terminalDir')}: $dirPath');
    }
  } catch (e) {
    if (context.mounted) {
      _showSnack(context, 'Failed to open terminal: $e', isError: true);
    }
  }
}

/// 公共自适应高度的毛玻璃容器卡片，统一风格。
class _GlassSectionCard extends StatelessWidget {
  const _GlassSectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
