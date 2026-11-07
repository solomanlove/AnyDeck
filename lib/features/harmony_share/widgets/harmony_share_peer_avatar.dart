import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_sizes.dart';
import '../model/harmony_share_peer_state.dart';
import 'harmony_share_drop_target.dart';

/// 圆形手机头像；state 提供真实批次状态，enabled 控制选文件与整组拖放。
/// onPick 与 onDrop 都交回页面确认，不在头像内启动传输或生成模拟进度。
class HarmonySharePeerAvatar extends StatelessWidget {
  const HarmonySharePeerAvatar({
    super.key,
    required this.state,
    required this.enabled,
    required this.onPick,
    required this.onDrop,
    required this.onInvalidDrop,
  });

  final HarmonySharePeerState state;
  final bool enabled;
  final VoidCallback onPick;
  final ValueChanged<List<File>> onDrop;
  final VoidCallback onInvalidDrop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final phase = state.phase;
    final color = phase == HarmonySharePeerPhase.failed
        ? colors.error
        : colors.primary;
    final waiting = phase == HarmonySharePeerPhase.waiting;
    final sending =
        phase == HarmonySharePeerPhase.sending ||
        phase == HarmonySharePeerPhase.confirming;
    final label = state.peer.name.isEmpty
        ? state.peer.address.address
        : state.peer.name;
    final status = phase == HarmonySharePeerPhase.ready
        ? ''
        : context.l10n.t('harmonySharePeer_${phase.name}');
    return HarmonyShareDropTarget(
      enabled: enabled,
      onDrop: (files) => files.isEmpty ? onInvalidDrop() : onDrop(files),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: '$label $status',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppThemeSizes.radiusLarge,
            onTap: enabled ? onPick : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 88,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.surfaceContainerHighest,
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          child: waiting
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.circle, size: 12, color: color),
                                    const SizedBox(width: 14),
                                    Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: color.withValues(alpha: .6),
                                    ),
                                  ],
                                )
                              : Icon(
                                  Icons.phone_android_rounded,
                                  size: 38,
                                  color: colors.onSurface,
                                ),
                        ),
                        if (sending)
                          Positioned.fill(
                            child: CircularProgressIndicator(
                              value: state.progress,
                              strokeWidth: 3,
                              color: color,
                              backgroundColor: colors.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (status.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: color),
                    ),
                  ],
                  if (state.fileCount > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      context.l10n
                          .t('harmonySharePeerBatch')
                          .replaceAll('{count}', '${state.fileCount}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (state.queuedBatches > 0)
                    Text(
                      context.l10n
                          .t('harmonySharePeerQueuedBatches')
                          .replaceAll('{count}', '${state.queuedBatches}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
