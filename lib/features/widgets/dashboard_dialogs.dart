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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ManualSection(
                title: context.l10n.t('softwareOverviewTitle'),
                body: context.l10n.t('softwareOverview'),
              ),
              _ManualSection(
                title: context.l10n.t('softwareRequirementsTitle'),
                body: context.l10n.t('softwareRequirements'),
              ),
              _ManualSection(
                title: context.l10n.t('softwareWorkflowTitle'),
                body: context.l10n.t('softwareWorkflow'),
              ),
              _ManualSection(
                title: context.l10n.t('softwareNoticeTitle'),
                body: context.l10n.t('softwareNotice'),
              ),
            ],
          ),
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

class _ManualSection extends StatelessWidget {
  const _ManualSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(body),
        ],
      ),
    );
  }
}


/// 设备发现卡片，已重构为响应式表格形式。
