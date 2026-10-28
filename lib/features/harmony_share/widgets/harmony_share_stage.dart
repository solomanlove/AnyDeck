import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_sizes.dart';
import '../../../core/nearby_share/share_core_client.dart';

/// 原型中的发现舞台。peers 为真实发现结果；onDrop 和 onPick 共用发送确认入口。
/// 不持有服务或动画 Timer，页面离开后不会新增后台负担。
class HarmonyShareStage extends StatelessWidget {
  const HarmonyShareStage({
    super.key,
    required this.peers,
    required this.enabled,
    required this.busy,
    required this.onPick,
    required this.onDrop,
    required this.onInvalidDrop,
  });

  final List<ShareCorePeer> peers;
  final bool enabled;
  final bool busy;
  final ValueChanged<ShareCorePeer> onPick;
  final void Function(ShareCorePeer, File) onDrop;
  final VoidCallback onInvalidDrop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: double.infinity,
          child: ClipRect(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.5, -0.3),
                  radius: 1.4,
                  colors: [colors.primaryContainer, colors.surfaceContainerLow],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _OrbitPainter(
                          colors.primary.withValues(alpha: .1),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        if (peers.isNotEmpty)
                          Wrap(
                            spacing: 16,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final peer in peers)
                                _PeerCard(
                                  peer: peer,
                                  enabled: enabled && !busy,
                                  onPick: () => onPick(peer),
                                  onDrop: (file) => onDrop(peer, file),
                                  onInvalidDrop: onInvalidDrop,
                                ),
                            ],
                          ),
                        const SizedBox(height: 24),
                        DropTarget(
                          // 设备卡片与中央区域不嵌套，避免一次拖放重复弹出确认。
                          onDragDone: (detail) {
                            if (busy || !enabled) return;
                            if (detail.files.length == 1 && peers.length == 1) {
                              onDrop(
                                peers.single,
                                File(detail.files.single.path),
                              );
                            } else {
                              onInvalidDrop();
                            }
                          },
                          child: Container(
                            width: 300,
                            height: 300,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.surface.withValues(alpha: .8),
                              border: Border.all(color: colors.outlineVariant),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.near_me_outlined,
                                  size: 36,
                                  color: colors.primary,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  context.l10n.t(
                                    !enabled
                                        ? 'harmonyShareDisabled'
                                        : peers.isEmpty
                                        ? 'harmonyShareEmpty'
                                        : 'harmonyShareDrop',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  context.l10n.t('harmonyShareTapDevice'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed:
                                      enabled && !busy && peers.length == 1
                                      ? () => onPick(peers.single)
                                      : null,
                                  child: Text(
                                    context.l10n.t('harmonySharePick'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 手机卡片以真实设备名展示；可键盘激活，也接受 Finder 单文件拖放。
class _PeerCard extends StatelessWidget {
  const _PeerCard({
    required this.peer,
    required this.enabled,
    required this.onPick,
    required this.onDrop,
    required this.onInvalidDrop,
  });
  final ShareCorePeer peer;
  final bool enabled;
  final VoidCallback onPick;
  final ValueChanged<File> onDrop;
  final VoidCallback onInvalidDrop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DropTarget(
      onDragDone: (detail) {
        if (!enabled) return;
        if (detail.files.length == 1) {
          onDrop(File(detail.files.single.path));
        } else {
          onInvalidDrop();
        }
      },
      child: SizedBox(
        width: 170,
        child: Material(
          color: colors.surface,
          borderRadius: AppThemeSizes.radiusLarge,
          child: InkWell(
            borderRadius: AppThemeSizes.radiusLarge,
            onTap: enabled ? onPick : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                    child: const Icon(Icons.smartphone_rounded, size: 32),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    peer.name.isEmpty ? peer.address.address : peer.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.t('harmonySharePeerReady'),
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

/// 静态同心圆替代持续动画；颜色由 Theme 注入。
class _OrbitPainter extends CustomPainter {
  const _OrbitPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    for (final radius in [170.0, 260.0, 350.0]) {
      canvas.drawCircle(size.center(Offset.zero), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) => color != oldDelegate.color;
}
