import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';

/// 按原型比例绘制手机外框，展示真实截图或设备品牌封面。
///
/// [width] 是外框宽度，高度由 9:18.5 比例计算；[online] 决定边框状态。
/// [screenshot] 只在在线时显示，缺失或解码失败时显示 [brand]、[title]、
/// [hint]，避免将模拟内容误当成真实设备屏幕。[semanticLabel] 为手机点击
/// 区提供本地化说明，[onTap] 由宿主实现投屏、重连或批量选择。
class DeviceWallPhone extends StatelessWidget {
  const DeviceWallPhone({
    super.key,
    required this.width,
    required this.online,
    required this.brand,
    required this.title,
    required this.hint,
    required this.semanticLabel,
    this.screenshot,
    this.onTap,
  });

  final double width;
  final bool online;
  final String brand;
  final String title;
  final String hint;
  final String semanticLabel;
  final Uint8List? screenshot;
  final VoidCallback? onTap;

  static const aspectRatio = 9 / 18.5;
  static const _frameRadius = BorderRadius.all(Radius.circular(22));
  static const _screenRadius = BorderRadius.all(Radius.circular(17));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width <= 490;
    final frameRadius = compact ? BorderRadius.circular(19) : _frameRadius;
    final screenRadius = compact ? BorderRadius.circular(14) : _screenRadius;
    final frameColor = online
        ? theme.appColors.toolbarForeground
        : theme.appColors.strongBorder;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -2,
              top: 58,
              width: 2,
              height: 26,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: frameColor,
                  borderRadius: AppThemeSizes.radiusSmall,
                ),
              ),
            ),
            Positioned(
              left: -2,
              top: 48,
              width: 2,
              height: 39,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: frameColor,
                  borderRadius: AppThemeSizes.radiusSmall,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: frameColor,
                  borderRadius: frameRadius,
                  boxShadow: online
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.shadow.withValues(
                              alpha: .09,
                            ),
                            offset: const Offset(0, 7),
                            blurRadius: 15,
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: frameRadius,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTap,
                    child: Semantics(
                      label: semanticLabel,
                      button: true,
                      enabled: onTap != null,
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: ClipRRect(
                          borderRadius: screenRadius,
                          child: ColoredBox(
                            color: theme.appColors.subtleSurface,
                            child: online && screenshot != null
                                ? Image.memory(
                                    screenshot!,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                    cacheWidth:
                                        (width *
                                                MediaQuery.devicePixelRatioOf(
                                                  context,
                                                ))
                                            .ceil(),
                                    errorBuilder: (_, _, _) => _cover(context),
                                  )
                                : _cover(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 9,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: frameColor,
                    ),
                    child: const SizedBox.square(dimension: 5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurfaceVariant;
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 15),
          // 封面是手机内的装饰信息；极长品牌名或大字号不应撑破固定外框。
          child: LayoutBuilder(
            builder: (context, constraints) => FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.smartphone, size: 25, color: foreground),
                    const SizedBox(height: 9),
                    Text(
                      brand,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: foreground),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 21,
          left: 5,
          right: 5,
          child: Text(
            hint,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: foreground),
          ),
        ),
        Positioned(
          bottom: 6,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: .65),
                borderRadius: AppThemeSizes.radiusSmall,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
