import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 统一加载本地 SVG 与位图资源，适用于品牌 Logo 等混合格式图片。
///
/// [assetName] 为已在 pubspec.yaml 声明的资源路径；[width]、[height] 控制尺寸，
/// [fit]、[alignment] 控制缩放与对齐。[semanticsLabel] 由调用方提供本地化描述；
/// [errorBuilder] 可自定义加载失败时的展示，默认使用主题色的破损图片图标。
/// 保留图片原色，灰度或主题着色可由外层 ColorFiltered 统一处理。
///
/// 示例：`AppAssetImage(AppIcons.xiaomiSvg, width: 32, height: 32)`。
class AppAssetImage extends StatelessWidget {
  const AppAssetImage(
    this.assetName, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.semanticsLabel,
    this.errorBuilder,
  });

  final String assetName;
  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final String? semanticsLabel;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    // SVG 必须交给矢量解码器，其余资源沿用 Flutter 的位图加载与缓存。
    if (assetName.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        assetName,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        semanticsLabel: semanticsLabel,
        errorBuilder: errorBuilder ?? _buildError,
      );
    }
    return Image.asset(
      assetName,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      semanticLabel: semanticsLabel,
      errorBuilder: errorBuilder ?? _buildError,
    );
  }

  Widget _buildError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return SizedBox(
      width: width,
      height: height,
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
