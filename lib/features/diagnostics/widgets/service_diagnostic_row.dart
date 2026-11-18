import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/diagnostics/service_diagnostic.dart';
import '../../../core/environment/connection_environment_service.dart';
import '../../devices/widgets/platform_environment_guide_dialog.dart';
import 'services_diagnostics_panel.dart';

/// 单项服务结果及原因、影响和建议；技术字段可选中复制，不包含凭据。
class ServiceDiagnosticRow extends ConsumerWidget {
  const ServiceDiagnosticRow({super.key, required this.result, this.checkedAt});
  final ServiceDiagnostic result;
  final DateTime? checkedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final expanded = ref.watch(expandedDiagnosticProvider) == result.service;
    final color = switch (result.status) {
      ServiceDiagnosticStatus.error => theme.colorScheme.error,
      ServiceDiagnosticStatus.missing ||
      ServiceDiagnosticStatus.permissionRequired => theme.appColors.warning,
      ServiceDiagnosticStatus.running ||
      ServiceDiagnosticStatus.ready => theme.appColors.success,
      _ => theme.appColors.mutedForeground,
    };
    final icon = result.needsAttention
        ? LucideIcons.circleAlert
        : result.status == ServiceDiagnosticStatus.running ||
              result.status == ServiceDiagnosticStatus.ready
        ? LucideIcons.circleCheck
        : result.status == ServiceDiagnosticStatus.notChecked ||
              result.status == ServiceDiagnosticStatus.checking
        ? LucideIcons.circleDashed
        : LucideIcons.circleMinus;
    final platform = switch (result.service) {
      DiagnosticService.adb => TargetPlatformType.android,
      DiagnosticService.hdc => TargetPlatformType.harmony,
      DiagnosticService.ios => TargetPlatformType.ios,
      _ => null,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.appColors.subtleDivider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            expanded: expanded,
            child: InkWell(
              key: ValueKey('diagnostic-row-${result.service.name}'),
              onTap: () => ref
                  .read(expandedDiagnosticProvider.notifier)
                  .toggle(result.service),
              borderRadius: AppThemeSizes.radiusSmall,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 宽屏状态按内容占宽，名称使用剩余空间；窄屏与大字号允许状态换行。
                    final compact =
                        constraints.maxWidth >= 420 &&
                        MediaQuery.textScalerOf(context).scale(11) <= 14;
                    final label = Text(
                      l10n.t('diagnosticsStatus${result.status.name}'),
                      style: TextStyle(fontSize: 11, color: color),
                    );
                    final status = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: color, size: 13),
                        const SizedBox(width: 4),
                        if (compact) label else Flexible(child: label),
                      ],
                    );
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.t(result.titleKey),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (compact) status else Flexible(child: status),
                        const SizedBox(width: 8),
                        Icon(
                          expanded
                              ? LucideIcons.chevronUp
                              : LucideIcons.chevronDown,
                          color: theme.appColors.mutedForeground,
                          size: 13,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _description(
                    context,
                    'diagnosticsResult',
                    l10n.t(result.reasonKey),
                  ),
                  _description(
                    context,
                    'diagnosticsImpact',
                    l10n.t(result.impactKey),
                  ),
                  _description(
                    context,
                    'diagnosticsAdvice',
                    l10n.t(result.adviceKey),
                  ),
                  for (final detail in result.details)
                    _description(
                      context,
                      detail.labelKey,
                      detail.labelKey == 'diagnosticsMessageKey'
                          ? l10n.t(detail.value)
                          : detail.value,
                      selectable: true,
                    ),
                  if (platform != null)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                        ),
                      ),
                      onPressed: () => PlatformEnvironmentGuideDialog.show(
                        context,
                        initialPlatform: platform,
                      ),
                      child: Text(l10n.t('diagnosticsToolGuide')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _description(
    BuildContext context,
    String key,
    String value, {
    bool selectable = false,
  }) {
    final text = '${context.l10n.t(key)} $value';
    final style = TextStyle(
      fontSize: 11,
      height: 1.5,
      color: Theme.of(context).appColors.mutedForeground,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: selectable
          ? SelectableText(text, style: style)
          : Text(text, style: style),
    );
  }
}
