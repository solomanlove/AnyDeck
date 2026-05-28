part of 'dashboard_screen.dart';

class _SelectedDeviceHeader extends ConsumerWidget {
  const _SelectedDeviceHeader({required this.device, this.sessions = const {}});

  final AdbDevice device;
  final Map<String, ScrcpySession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSessions = sessions.values
        .where((session) => session.deviceId == device.id)
        .toList(growable: false);

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
            Icons.phone_android,
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
              _HeaderIconAction(
                icon: const Icon(Icons.cast, size: 18),
                tooltip: context.l10n.t('start'),
                onPressed: device.isOnline
                    ? () => _startScrcpy(context, ref, device.id)
                    : null,
              ),
              const SizedBox(width: 8),
              if (activeSessions.isNotEmpty) ...[
                _HeaderIconAction(
                  icon: const Icon(Icons.stop, size: 18),
                  tooltip: context.l10n.t('stopAll'),
                  filled: false,
                  onPressed: () => _stopSessions(context, ref, activeSessions),
                ),
                const SizedBox(width: 8),
                for (final session in activeSessions) ...[
                  InputChip(
                    avatar: const Icon(Icons.cast_connected, size: 18),
                    label: Text('PID ${session.pid}'),
                    onDeleted: () => _stopSessions(context, ref, [session]),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
              Chip(
                label: Text(device.status),
                avatar: Icon(
                  device.isOnline ? Icons.check_circle : Icons.warning_amber,
                  size: 18,
                ),
              ),
            ],
          );
          final closeButton = IconButton(
            icon: const Icon(Icons.close),
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

  /// 停止选中的会话，并从 UI 中移除对应 Chip。
  Future<void> _stopSessions(
    BuildContext context,
    WidgetRef ref,
    List<ScrcpySession> sessions,
  ) async {
    final service = ref.read(scrcpyServiceProvider);
    for (final session in sessions) {
      await service.stop(session.id);
    }
    ref
        .read(scrcpySessionsProvider.notifier)
        .removeAll(sessions.map((session) => session.id));
    if (context.mounted) {
      _showSnack(context, context.l10n.t('scrcpyStopped'));
    }
  }
}

/// 顶部设备 Header 中使用的纯图标操作按钮。
class _HeaderIconAction extends StatelessWidget {
  const _HeaderIconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = true,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(56, 56),
        foregroundColor: filled ? colorScheme.onPrimary : colorScheme.primary,
        backgroundColor: filled ? colorScheme.primary : Colors.transparent,
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
        disabledBackgroundColor: filled
            ? colorScheme.onSurface.withValues(alpha: 0.12)
            : Colors.transparent,
        side: filled ? BorderSide.none : BorderSide(color: colorScheme.outline),
        shape: shape,
      ),
    );
  }
}
