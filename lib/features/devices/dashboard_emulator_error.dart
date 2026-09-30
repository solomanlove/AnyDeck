part of '../dashboard_screen.dart';

/// 根据错误语义生成本地化说明，保留原始进程输出和退出码便于排查。
String _emulatorErrorText(BuildContext context, EmulatorLaunchState launch) {
  final summary = context.l10n
      .t(launch.errorKey!)
      .replaceAll('{code}', '${launch.exitCode ?? '-'}');
  return launch.details.isEmpty ? summary : '$summary\n${launch.details}';
}

/// 行内优先显示真正的错误行，避免 INFO 日志把失败原因挤出两行摘要。
String _emulatorErrorSummary(BuildContext context, EmulatorLaunchState launch) {
  if (launch.isConnectionIssue) return context.l10n.t(launch.errorKey!);
  final lines = launch.details.split('\n');
  final errorPattern = RegExp(
    r'error|panic|fatal|missing|failed|exception',
    caseSensitive: false,
  );
  for (final line in lines) {
    if (errorPattern.hasMatch(line)) return line.trim();
  }
  return _emulatorErrorText(context, launch);
}

/// 列表中的错误入口；点击可查看、选择和复制完整诊断。
class _EmulatorErrorButton extends StatelessWidget {
  const _EmulatorErrorButton({required this.launch});

  final EmulatorLaunchState launch;

  @override
  Widget build(BuildContext context) {
    final message = _emulatorErrorText(context, launch);
    final title = context.l10n.t(launch.isConnectionIssue ? 'emulatorAdbHelp' : 'emulatorViewError');
    return IconButton(
      tooltip: title,
      icon: Icon(
        launch.isConnectionIssue ? Icons.link_off : Icons.error_outline,
        color: launch.isConnectionIssue ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.error,
      ),
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(child: SelectableText(message)),
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: message)),
              child: Text(context.l10n.t('emulatorCopyError')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.t('close')),
            ),
          ],
        ),
      ),
    );
  }
}
