part of '../dashboard_screen.dart';

class _SelectedDeviceHeader extends ConsumerWidget {
  const _SelectedDeviceHeader({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffeceef1), width: 1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final icon = Icon(
            CupertinoIcons.device_phone_portrait,
            size: 38,
            color: Theme.of(context).colorScheme.primary,
          );
          final title = Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xff202124),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                device.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xff202124),
                ),
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // scrcpy 投屏控制区：只展示图标，完整语义放在 tooltip。
              IconButton(
                icon: const Icon(CupertinoIcons.tv),
                tooltip: context.l10n.t('start'),
                onPressed: device.isOnline
                    ? () => _startScrcpy(context, ref, device.id)
                    : null,
              ),
              const SizedBox(width: 8),

              Chip(
                label: Text(device.status),
                avatar: Icon(
                  device.isOnline ? CupertinoIcons.checkmark_circle : CupertinoIcons.exclamationmark_triangle,
                  size: 18,
                ),
              ),
            ],
          );
          final closeButton = IconButton(
            icon: const Icon(CupertinoIcons.xmark),
            tooltip: context.l10n.t('close'),
            onPressed: () {
              ref.read(userClearedDeviceSelectionProvider.notifier).state =
                  true;
              ref.read(selectedDeviceProvider.notifier).clear();
            },
          );

          if (constraints.maxWidth < 260) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: 14),
                  SizedBox(width: 160, child: title),
                  const SizedBox(width: 16),
                  actions,
                  const SizedBox(width: 8),
                  closeButton,
                ],
              ),
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 14),
              Expanded(child: title),
              const SizedBox(width: 16),
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: actions,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              closeButton,
            ],
          );
        },
      ),
    );
  }

  /// 启动 scrcpy，并将返回的进程元数据记录到 Riverpod 状态。
  Future<void> _startScrcpy(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    try {
      final session = await ref
          .read(scrcpyServiceProvider)
          .start(deviceId: deviceId, options: const ScrcpyLaunchOptions());
      ref.read(scrcpySessionsProvider.notifier).add(session);
      if (context.mounted) {
        _showSnack(
          context,
          '${context.l10n.t('scrcpyStarted')}: PID ${session.pid}',
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showSnack(context, error.toString(), isError: true);
      }
    }
  }
}
