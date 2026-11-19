import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../controller/service_diagnostics_controller.dart';
import 'services_diagnostics_panel.dart';

/// 底部状态栏的全局服务入口；闲置时仅读取快照，不自动探测或启动服务。
///
/// 可直接放入状态栏 Row。点击后按右下角展开最多 500px 的诊断面板，
/// 保留设备页状态，ESC / 点击外侧关闭并由 Dialog 恢复入口焦点。
/// [foregroundColor] 可将文字、图标与加载指示器统一到所在状态栏的前景色。
class ServicesDiagnosticsButton extends ConsumerWidget {
  const ServicesDiagnosticsButton({super.key, this.foregroundColor});

  final Color? foregroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final count = ref.watch(
      serviceDiagnosticsProvider.select((s) => s.issueCount),
    );
    final checking = ref.watch(
      serviceDiagnosticsProvider.select((s) => s.isChecking),
    );
    return TextButton.icon(
      key: const ValueKey('services-diagnostics-button'),
      onPressed: () => showServicesDiagnostics(context),
      style: TextButton.styleFrom(
        foregroundColor:
            foregroundColor ?? Theme.of(context).appColors.toolbarForeground,
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontSize: 11),
        visualDensity: VisualDensity.compact,
        shape: const RoundedRectangleBorder(
          borderRadius: AppThemeSizes.radiusSmall,
        ),
      ),
      icon: checking
          ? SizedBox.square(
              dimension: 13,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: foregroundColor,
              ),
            )
          : const Icon(LucideIcons.activity, size: 14),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(l10n.t('diagnosticsTitle'))),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: AppThemeSizes.radiusSmall,
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 桌面从右下方展开，窄窗口约束宽高并允许面板内容滚动。
Future<void> showServicesDiagnostics(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (dialogContext) {
      final media = MediaQuery.of(dialogContext);
      final available = media.size.height - media.padding.vertical - 16 - 42;
      return Dialog(
        alignment: Alignment.bottomRight,
        insetPadding: const EdgeInsets.fromLTRB(16, 16, 16, 42),
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppThemeSizes.radiusLarge,
          side: BorderSide(
            color: Theme.of(dialogContext).colorScheme.outlineVariant,
          ),
        ),
        child: SizedBox(
          width: 500,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.max(120, available)),
            child: ServicesDiagnosticsPanel(
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ),
      );
    },
  );
}
