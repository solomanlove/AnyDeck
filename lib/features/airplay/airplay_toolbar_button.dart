import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/widget/app_toast.dart';
import '../../core/airplay/airplay_server_service.dart';
import '../../core/airplay/airplay_server_state.dart';

/// 主窗口顶部工具栏优雅的 AirPlay 广播开关按钮。
///
/// 支持三种状态反馈：
/// 1. 空闲未广播：默认灰色状态，点击后开启广播并暴露 mDNS 局域网服务；
/// 2. 广播中（等待连接）：高亮主题色，带呼吸光点，提示正在广播待连接；
/// 3. 投屏中（已镜像）：鲜艳绿色激活态，提示当前正有 iPhone 连接投屏。
class AirPlayToolbarButton extends ConsumerStatefulWidget {
  const AirPlayToolbarButton({
    super.key,
    required this.iconColor,
  });

  /// 默认未激活状态下的图标颜色（跟随主窗口明暗主题）
  final Color iconColor;

  @override
  ConsumerState<AirPlayToolbarButton> createState() => _AirPlayToolbarButtonState();
}

class _AirPlayToolbarButtonState extends ConsumerState<AirPlayToolbarButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleToggle(AirPlaySessionData? session) async {
    if (_isProcessing) return;
    if (!Platform.isMacOS) {
      AppToast.show(context, 'AirPlay Server 目前仅支持 macOS 平台');
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final notifier = ref.read(airplaySessionProvider.notifier);
      if (session == null || session.status == AirPlayServerStatus.stopped) {
        await notifier.startServer();
        if (mounted) {
          AppToast.show(
            context,
            context.l10n.t('airplayBroadcasting').replaceAll('{name}', 'AnyDeck-AirPlay'),
          );
        }
      } else {
        await notifier.stopServer();
        if (mounted) {
          AppToast.show(context, context.l10n.t('airplayStopBroadcast'));
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'AirPlay 操作失败: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(airplaySessionProvider);
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final isBroadcasting = session != null && session.status == AirPlayServerStatus.idle;
    final isMirroring = session != null && session.status == AirPlayServerStatus.mirroring;

    // 计算当前按钮外观与提示文案
    final Color buttonColor;
    final String tooltip;
    if (isMirroring) {
      buttonColor = const Color(0xff34c759); // iOS 经典绿色激活指示
      tooltip = context.l10n.t('airplayMirroring');
    } else if (isBroadcasting) {
      buttonColor = primaryColor;
      tooltip = context.l10n.t('airplayBroadcasting').replaceAll('{name}', session.serverName);
    } else {
      buttonColor = widget.iconColor;
      tooltip = context.l10n.t('airplayStartBroadcast');
    }

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: _isProcessing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Icon(
                    Icons.airplay_rounded,
                    size: 26,
                    color: buttonColor,
                  ),
            onPressed: () => _handleToggle(session),
            style: IconButton.styleFrom(
              fixedSize: const Size(48, 48),
              backgroundColor: (isBroadcasting || isMirroring)
                  ? buttonColor.withValues(alpha: 0.12)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: (isBroadcasting || isMirroring)
                    ? BorderSide(color: buttonColor.withValues(alpha: 0.35), width: 1.2)
                    : BorderSide.none,
              ),
            ),
          ),
          // 广播中（待连接）或已镜像状态下的呼吸状态角标
          if (isBroadcasting || isMirroring)
            Positioned(
              top: 6,
              right: 6,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: isBroadcasting ? _pulseAnimation.value : 1.0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: buttonColor,
                        boxShadow: [
                          BoxShadow(
                            color: buttonColor.withValues(alpha: 0.6),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
