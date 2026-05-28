part of 'dashboard_screen.dart';

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
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
            icon: const Icon(Icons.add_link),
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
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) {
    return;
  }

  final media = MediaQuery.of(context);
  final accentColor = isError
      ? Theme.of(context).colorScheme.error
      : const Color(0xff00c853);
  final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
    color: const Color(0xff171a21),
    fontWeight: FontWeight.w600,
  );

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      return Positioned(
        top: media.padding.top + 16,
        left: 16,
        right: 16,
        child: IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: media.size.width - 64),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xffd7dce5)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isError ? Icons.error : Icons.check_circle,
                        color: accentColor,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Flexible(child: Text(message, style: textStyle)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  Timer(const Duration(seconds: 2), () {
    if (entry.mounted) {
      entry.remove();
    }
  });
}

/// 拼接远程目录路径和文件名，不参与宿主机路径处理。
String _joinRemotePath(String base, String name) {
  final normalized = base.endsWith('/') ? base : '$base/';
  return '$normalized$name';
}

/// 根据解析出的远程文件类型选择图标。
IconData _fileIcon(RemoteFile file) {
  return switch (file.type) {
    RemoteFileType.folder => Icons.folder,
    RemoteFileType.link => Icons.link,
    RemoteFileType.file => Icons.insert_drive_file_outlined,
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
