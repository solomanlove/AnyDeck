import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../l10n/app_localizations.dart';

/// AirPlay 投屏断开连接美化提示组件。
///
/// 用途：
/// 当 iPhone 手机端主动断开隔空播放、或连接意外中断时展示。
/// 满幅适配不同纵横比的独立投屏小窗口，提供 macOS 质感的半透明磨砂毛玻璃卡片、
/// 优雅的失连状态提示，以及一键关闭窗口等操作。
///
/// 参数说明：
/// - [deviceName]: 投屏设备广播名称，用于重连文案提示。
/// - [onClose]: 可选的关闭窗口回调，为空时默认调用 `windowManager.close()`。
class AirPlayDisconnectedView extends StatelessWidget {
  const AirPlayDisconnectedView({
    super.key,
    required this.deviceName,
    this.onClose,
  });

  /// 投屏设备广播名称
  final String deviceName;

  /// 自定义关闭窗口回调
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 自适应背景渐变
    final bgGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? const [
              Color(0xFF1E1F24),
              Color(0xFF141418),
            ]
          : const [
              Color(0xFFF7F7FA),
              Color(0xFFEBEBF0),
            ],
    );

    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 失连指示图标带柔和底盘
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? const Color(0xFF2A2A32)
                          : const Color(0xFFE2E4EC),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.airplay_rounded,
                        size: 32,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.45)
                            : Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 主标题
                  Text(
                    context.l10n.t('airplayDisconnected'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 副标题与引导文案
                  Text(
                    context.l10n.t('airplayDisconnectedSubtitle'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.55)
                          : Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n
                        .t('airplayReconnectHint')
                        .replaceAll('{name}', deviceName),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.38)
                          : Colors.black.withValues(alpha: 0.38),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // 操作按钮
                  SizedBox(
                    height: 36,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.16)
                              : Colors.black.withValues(alpha: 0.12),
                          width: 1,
                        ),
                      ),
                      onPressed: () {
                        if (onClose != null) {
                          onClose!();
                        } else {
                          windowManager.close();
                        }
                      },
                      icon: const Icon(CupertinoIcons.xmark, size: 14),
                      label: Text(
                        context.l10n.t('airplayCloseWindow'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
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
