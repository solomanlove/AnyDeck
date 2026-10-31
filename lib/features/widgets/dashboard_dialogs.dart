part of '../dashboard_screen.dart';

/// 软件说明书弹窗，覆盖启动前准备和常用调试流程。
class _SoftwareManualDialog extends StatelessWidget {
  const _SoftwareManualDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.t('softwareManual')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: const SoftwareManualContent(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('close')),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 72, child: Text(label, style: textTheme.bodyMedium)),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// 设备发现卡片，已重构为响应式表格形式。
