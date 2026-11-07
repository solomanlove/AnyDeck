import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/nearby_share/harmony_share_send_queue.dart';
import '../../../core/nearby_share/share_core_client.dart';
import '../model/harmony_share_peer_state.dart';
import 'harmony_share_peer_avatar.dart';
import 'harmony_share_scan_backdrop.dart';

/// 固定高度的发现舞台；空状态与设备列表共用同一背景，设备数量不改变高度。
/// header/footer 为身份栏和连接提示，batches 只提供真实发送批次快照。
/// starting 仅表示等待 Core 的发现就绪确认，不冒充已开始扫描。
/// directMode 就绪后提示从手机分享，不将等待来件显示成 LAN 设备搜索。
/// busy 只控制能否选文件，scanning 独立控制发现动画，允许发送中追加下一批。
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
    this.unavailable = false,
    this.starting = false,
    this.directMode = false,
    this.batches = const [],
    this.activeBatchId,
    this.cancelling = false,
    this.header,
    this.footer,
  });

  final Widget? header;
  final Widget? footer;
  final List<ShareCorePeer> peers;
  final List<ShareSendBatch> batches;
  final String? activeBatchId;
  final bool cancelling;
  final bool enabled;
  final bool busy;
  final bool scanning;
  final bool unavailable;
  final bool starting;
  final bool directMode;
  final ValueChanged<ShareCorePeer> onPick;
  final void Function(ShareCorePeer, List<File>) onDrop;
  final VoidCallback onInvalidDrop;

  /// 发现区域始终占相同高度；更多设备在内部滚动，不撑高背景或推走底栏。
  static const contentHeight = 396.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final devices = HarmonySharePeerState.resolve(
      peers: peers,
      batches: batches,
      activeBatchId: activeBatchId,
      cancelling: cancelling,
    );
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
            children: [
              // 背景先绘制，保证波纹位于身份、设备头像和底部文字下方。
              Positioned.fill(
                child: IgnorePointer(
                  child: HarmonyShareScanBackdrop(
                    active: scanning && enabled && !busy && !directMode,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?header,
                  SizedBox(
                    key: const ValueKey('harmony-share-discovery-content'),
                    height: contentHeight,
                    width: double.infinity,
                    child: devices.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                context.l10n.t(
                                  !enabled
                                      ? 'harmonyShareDisabled'
                                      : unavailable
                                      ? 'harmonyShareUnavailable'
                                      : busy
                                      ? 'harmonyShareWaiting'
                                      : starting
                                      ? 'harmonyShareStartingDiscovery'
                                      : directMode
                                      ? 'harmonyShareDirectReady'
                                      : 'harmonyShareSearching',
                                ),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  context.l10n.t(
                                    devices.any((device) => !device.available)
                                        ? 'harmonyShareTransferDevices'
                                        : 'harmonySharePeerSection',
                                  ),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: GridView.builder(
                                    primary: false,
                                    padding: EdgeInsets.zero,
                                    gridDelegate:
                                        SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: 190,
                                          mainAxisExtent:
                                              280 *
                                              MediaQuery.textScalerOf(
                                                context,
                                              ).scale(14) /
                                              14,
                                          crossAxisSpacing: 16,
                                          mainAxisSpacing: 12,
                                        ),
                                    itemCount: devices.length,
                                    itemBuilder: (context, index) {
                                      final device = devices[index];
                                      final canPick =
                                          enabled && !busy && device.available;
                                      // 网格预留状态空间，头像点击/高亮区域只包裹实际内容。
                                      return Align(
                                        alignment: Alignment.topCenter,
                                        child: HarmonySharePeerAvatar(
                                          key: ValueKey(
                                            HarmonySharePeerState.identity(
                                              device.peer,
                                            ),
                                          ),
                                          state: device,
                                          enabled: canPick,
                                          onPick: () => onPick(device.peer),
                                          onDrop: (files) =>
                                              onDrop(device.peer, files),
                                          onInvalidDrop: onInvalidDrop,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  ?footer,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
