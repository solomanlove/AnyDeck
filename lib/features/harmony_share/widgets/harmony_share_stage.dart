import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_sizes.dart';
import '../../../core/nearby_share/share_core_client.dart';
import 'harmony_share_drop_target.dart';
import 'harmony_share_scan_backdrop.dart';

/// 原型中的发现舞台。peers 为真实发现结果；onDrop 和 onPick 共用发送确认入口。
/// scanning 由服务明确提供，收发/关闭/不可用时保持静态；动画在独立重绘层。
class HarmonyShareStage extends StatelessWidget {
  const HarmonyShareStage({
    super.key,
    required this.peers,
    required this.enabled,
    required this.busy,
    required this.onPick,
    required this.onDrop,
    required this.onInvalidDrop,
    this.scanning = false,
    this.header,
    this.footer,
  });

  /// 可选身份栏和连接提示；共用舞台背景，不遮挡向外扩散的扫描波纹。
  final Widget? header;
  final Widget? footer;
  final List<ShareCorePeer> peers;
  final bool enabled;
  final bool busy;
  final bool scanning;
  final ValueChanged<ShareCorePeer> onPick;
  final void Function(ShareCorePeer, List<File>) onDrop;
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?header,
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                        // 以中央投递区为扫描圆心，设备卡片换行不会移动波纹中心。
                        SizedBox(
                          width: double.infinity,
                          height: 348,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              // 扩大绘制层到完整波纹直径，由最外层统一裁剪，
                              // 保持圆心跟随投递区，身份栏/底栏下方也能绘制。
                              Positioned(
                                top:
                                    (348 - HarmonyShareScanBackdrop.diameter) /
                                    2,
                                bottom:
                                    (348 - HarmonyShareScanBackdrop.diameter) /
                                    2,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(
                                  child: HarmonyShareScanBackdrop(
                                    active: scanning && enabled && !busy,
                                  ),
                                ),
                              ),
                              HarmonyShareDropTarget(
                                enabled: enabled && !busy,
                                circular: true,
                                // 设备卡片与中央区域不嵌套，避免一次拖放重复弹出确认。
                                onDrop: (files) {
                                  if (busy || !enabled) return;
                                  if (files.isNotEmpty && peers.length == 1) {
                                    onDrop(peers.single, files);
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
                                    border: Border.all(
                                      color: colors.outlineVariant,
                                    ),
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
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton(
                                        onPressed:
                                            enabled &&
                                                !busy &&
                                                peers.length == 1
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
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?footer,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 手机卡片以真实设备名展示；可键盘激活，也接受 Finder 多文件拖放。
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
  final ValueChanged<List<File>> onDrop;
  final VoidCallback onInvalidDrop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return HarmonyShareDropTarget(
      enabled: enabled,
      onDrop: (files) {
        if (!enabled) return;
        if (files.isNotEmpty) {
          onDrop(files);
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
