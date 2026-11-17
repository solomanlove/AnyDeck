import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/diagnostics/service_diagnostic.dart';
import '../controller/service_diagnostics_controller.dart';
import 'service_diagnostic_row.dart';

/// 服务诊断主体；[onClose] 关闭承载浮层，不停止任何实际服务。
class ServicesDiagnosticsPanel extends ConsumerWidget {
  const ServicesDiagnosticsPanel({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serviceDiagnosticsProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final summary = state.isChecking
        ? l10n.t('diagnosticsChecking')
        : state.checkedAt == null
        ? l10n.t('diagnosticsNotChecked')
        : state.issueCount == 0
        ? l10n.t('diagnosticsNoIssues')
        : l10n
              .t('diagnosticsIssueCount')
              .replaceAll('{count}', '${state.issueCount}');
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const ValueKey('services-diagnostics-panel'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('diagnosticsTitle'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.t('diagnosticsSubtitle'),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.appColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('services-diagnostics-close'),
                autofocus: true,
                tooltip: l10n.t('close'),
                onPressed: onClose,
                icon: const Icon(LucideIcons.x, size: 15),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: const EdgeInsets.all(4),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final summaryLabel = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      summary,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.t('diagnosticsReadOnly'),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.appColors.mutedForeground,
                    ),
                  ),
                ],
              );
              final runButton = FilledButton.icon(
                key: const ValueKey('services-diagnostics-run'),
                onPressed: state.isChecking
                    ? null
                    : () => ref.read(serviceDiagnosticsProvider.notifier).run(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                  textStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppThemeSizes.radiusMedium,
                  ),
                ),
                icon: state.isChecking
                    ? const SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(LucideIcons.scanLine, size: 14),
                label: Text(
                  l10n.t(
                    state.isChecking
                        ? 'diagnosticsChecking'
                        : state.checkedAt == null
                        ? 'diagnosticsStart'
                        : 'diagnosticsRerun',
                  ),
                ),
              );
              if (constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(11) > 14) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summaryLabel,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: runButton),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: summaryLabel),
                  const SizedBox(width: 10),
                  runButton,
                ],
              );
            },
          ),
          const SizedBox(height: 13),
          Divider(height: 1, color: theme.appColors.subtleDivider),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final result in state.orderedEntries)
                    ServiceDiagnosticRow(
                      result: result,
                      checkedAt: state.checkedAt,
                    ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.t('diagnosticsScope'),
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.5,
                      color: theme.appColors.mutedForeground,
                    ),
                  ),
                  if (state.checkedAt case final time?) ...[
                    const SizedBox(height: 5),
                    Text(
                      '${l10n.t('diagnosticsCheckedAt')} '
                      '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(time), alwaysUse24HourFormat: true)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.appColors.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一次只展开一个服务；仅在面板存活时保留展开状态。
final expandedDiagnosticProvider =
    NotifierProvider.autoDispose<
      ExpandedDiagnosticController,
      DiagnosticService?
    >(ExpandedDiagnosticController.new);

class ExpandedDiagnosticController extends Notifier<DiagnosticService?> {
  @override
  DiagnosticService? build() => null;
  void toggle(DiagnosticService service) =>
      state = state == service ? null : service;
}
