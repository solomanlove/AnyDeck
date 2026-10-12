import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/airplay/airplay_server_service.dart';
import '../../../core/airplay/airplay_server_state.dart';
import '../../../core/providers/app_providers.dart';
import '../airplay_mirror_target.dart';

/// AirPlay 投屏活跃状态横幅组件。
///
/// 用途：
/// 当有 iPhone/iPad 正在通过 AirPlay 屏幕镜像投屏到本电脑时，在设备列表上方展示此横幅。
/// 即使投屏小窗口被用户关闭，用户仍可在此处一键【重新打开投屏窗口】，
/// 也可以在此处点击【彻底停止投屏】通知手机端退出镜像。
class AirPlayActiveBanner extends ConsumerWidget {
  const AirPlayActiveBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(airplaySessionProvider);
    if (session == null || session.status != AirPlayServerStatus.mirroring) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final deviceName = session.clientName ?? 'iPhone';
    final resolutionStr = (session.width > 0 && session.height > 0)
        ? '${session.width} × ${session.height}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E3A2B).withValues(alpha: 0.6)
            : const Color(0xFFE8F5E9).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF34C759).withValues(alpha: isDark ? 0.35 : 0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // 活跃呼吸绿点与 AirPlay 图标
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF34C759).withValues(alpha: 0.2),
            ),
            child: const Icon(
              Icons.airplay_rounded,
              size: 16,
              color: Color(0xFF34C759),
            ),
          ),
          const SizedBox(width: 10),

          // 设备名与分辨率描述
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '$deviceName · ${context.l10n.t('airplayMirrorActive')}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF34C759),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                if (resolutionStr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${context.l10n.t('resolution')}: $resolutionStr',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),

          // 操作按钮 1：重新打开投屏窗口
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF34C759),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              final preferred = resolveAirPlayMirrorTarget(
                ref.read(deviceRegistryProvider),
              );
              openAirPlayMirrorWindow(
                session,
                deviceId: preferred?.id,
                deviceName: preferred?.displayName,
              );
            },
            icon: const Icon(CupertinoIcons.tv, size: 14),
            label: Text(
              context.l10n.t('airplayOpenMirrorWindow'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),

          // 操作按钮 2：彻底断开投屏
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              side: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.15),
              ),
            ),
            onPressed: () {
              ref.read(airplaySessionProvider.notifier).stopServer();
            },
            child: Text(
              context.l10n.t('airplayStopSession'),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).appColors.toolbarForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
