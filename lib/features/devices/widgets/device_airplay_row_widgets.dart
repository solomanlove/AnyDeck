import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/airplay/airplay_server_service.dart';
import '../../../core/airplay/airplay_server_state.dart';
import '../../../core/providers/modules/registered_device_model.dart';

/// 设备列表行内的 AirPlay LIVE 状态胶囊徽章。
///
/// 用途：
/// 在设备名称右侧展示紧凑的绿色 `AirPlay LIVE` 标识，替代原顶部独立横幅中的状态提示。
///
/// 用法：
/// ```dart
/// const DeviceAirPlayLiveBadge()
/// ```
class DeviceAirPlayLiveBadge extends StatelessWidget {
  const DeviceAirPlayLiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFF34C759).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFF34C759).withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: const Text(
        'AirPlay LIVE',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF34C759),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// 设备列表操作列中的 AirPlay 纯图标极简按钮组（方案 C）。
///
/// 用途：
/// 当设备正处于 AirPlay 投屏状态时，在列表操作列并排展示【打开投屏窗口】与【彻底停止投屏】纯图标按钮，
/// 与 Android/iOS 常规图标操作列风格保持一致。
///
/// 参数说明：
/// - [device]: 当前行关联的已注册或虚拟设备模型；
/// - [session]: 当前行绑定的活跃 AirPlay 投屏会话数据。
class DeviceAirPlayActionButtons extends ConsumerWidget {
  const DeviceAirPlayActionButtons({
    super.key,
    required this.device,
    required this.session,
  });

  /// 当前设备行模型
  final RegisteredDevice device;

  /// 当前设备绑定的 AirPlay 活跃会话
  final AirPlaySessionData session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. 打开投屏窗口图标按钮
        Tooltip(
          message: context.l10n.t('airplayOpenMirrorWindow'),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => openAirPlayMirrorWindow(
              session,
              deviceId: device.id,
              deviceName: device.displayName,
            ),
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF34C759).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF34C759).withValues(alpha: 0.45),
                  width: 0.8,
                ),
              ),
              child: const Icon(
                Icons.airplay_rounded,
                size: 14,
                color: Color(0xFF34C759),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // 2. 彻底停止当前设备 AirPlay 投屏图标按钮
        Tooltip(
          message: context.l10n.t('airplayStopSession'),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              ref.read(airplaySessionProvider.notifier).stopSession(session.id);
            },
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: const Icon(
                CupertinoIcons.stop_fill,
                size: 12,
                color: Colors.redAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
