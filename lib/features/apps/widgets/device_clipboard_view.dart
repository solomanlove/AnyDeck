import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/device_capture_compatibility.dart';
import '../controller/device_auxiliary_controller.dart';
import 'capture_compatibility_view.dart';

/// 手机文本剪贴板实时面板；显示本地列表，最新内容实时在最顶部。
/// deviceId 为 ADB serial，离开页面清空内存文本并停止独立连接。
class DeviceClipboardView extends ConsumerWidget {
  const DeviceClipboardView({super.key, required this.deviceId});
  final String deviceId;

  Future<void> _copyText(BuildContext context, String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(context.l10n.t('clipboardCopied')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(context.l10n.t('clipboardCopyFailed')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (deviceId: deviceId, microphone: false);
    final state = ref.watch(deviceAuxiliaryProvider(key));
    final controller = ref.read(deviceAuxiliaryProvider(key).notifier);
    final sdk = ref.watch(captureSdkProvider(deviceId)).value;
    final online = ref.watch(deviceOnlineProvider(deviceId));
    final colors = Theme.of(context).colorScheme;
    final history = state.history;
    final latestText = history.firstOrNull?.text ?? state.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(context.l10n.t('clipboardIntro')),
        CaptureCompatibilityView(deviceId: deviceId, kind: 'clipboard'),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed:
                  online &&
                          ref.watch(captureHostSupportedProvider) &&
                          (sdk ?? 0) >= 21 &&
                          !state.busy &&
                          !state.active
                      ? controller.start
                      : null,
              icon: const Icon(Icons.content_paste_search),
              label: Text(context.l10n.t('clipboardStart')),
            ),
            OutlinedButton(
              onPressed:
                  (state.active || state.busy) &&
                          state.messageKey != 'auxStopping'
                      ? () => controller.stop()
                      : null,
              child: Text(context.l10n.t('clipboardStop')),
            ),
            TextButton(
              onPressed: state.active && !state.busy ? controller.refresh : null,
              child: Text(context.l10n.t('clipboardRefresh')),
            ),
            TextButton.icon(
              onPressed:
                  latestText == null ? null : () => _copyText(context, latestText),
              icon: const Icon(Icons.copy, size: 16),
              label: Text(context.l10n.t('clipboardCopy')),
            ),
            TextButton.icon(
              onPressed: history.isNotEmpty ? controller.clearHistory : null,
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: Text(context.l10n.t('clipboardClear')),
            ),
          ],
        ),
        if (state.busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.t(state.messageKey),
                  style: TextStyle(
                    color: state.failed ? colors.error : colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (history.isNotEmpty)
                Text(
                  '${history.length} ${context.l10n.t('clipboardCount')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: history.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SelectableText(
                        state.text ?? context.l10n.t('clipboardEmptyNote'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: history.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = history[index];
                      final isLatest = index == 0;
                      return Container(
                        decoration: BoxDecoration(
                          color: isLatest
                              ? colors.primaryContainer.withValues(alpha: 0.35)
                              : colors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isLatest
                                ? colors.primary.withValues(alpha: 0.5)
                                : colors.outlineVariant.withValues(alpha: 0.4),
                            width: isLatest ? 1.5 : 1.0,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                if (isLatest) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.primary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      context.l10n.t('clipboardLatest'),
                                      style: TextStyle(
                                        color: colors.onPrimary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    item.receivedAt
                                        .toLocal()
                                        .toString()
                                        .split('.')
                                        .first,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 16),
                                  tooltip: context.l10n.t('clipboardCopy'),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                  onPressed: () => _copyText(context, item.text),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              item.text,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
