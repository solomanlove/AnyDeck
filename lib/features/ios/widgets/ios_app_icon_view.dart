import 'dart:io';
import 'package:flutter/material.dart';

/// iOS 应用图标展示组件。
///
/// 用于根据已提取的本地图标文件路径渲染 iOS 风格的圆角应用图标；
/// 若图标尚未下载或读取失败，则优雅降级为系统设置齿轮或应用网格占位。
///
/// 参数说明：
/// - [iconPath] 本地 PNG 图标的完整路径，若为 null 则展示占位图标。
/// - [bundleId] 应用的 Bundle Identifier，用于生成语义化标签或备用提示。
/// - [system] 是否为 iOS 系统级应用，系统级应用占位为齿轮，用户应用占位为应用方块。
/// - [size] 图标渲染的边长大小，默认 40.0，圆角按 iOS 经典的 0.22 比例自适应缩放。
///
/// 用法示例：
/// ```dart
/// IosAppIconView(
///   iconPath: app.iconPath,
///   bundleId: app.bundleId,
///   system: app.system,
///   size: 42,
/// )
/// ```
class IosAppIconView extends StatelessWidget {
  const IosAppIconView({
    super.key,
    this.iconPath,
    required this.bundleId,
    this.system = false,
    this.size = 40.0,
  });

  /// 本地图标文件绝对路径
  final String? iconPath;

  /// Bundle Identifier
  final String bundleId;

  /// 是否为系统应用
  final bool system;

  /// 图标宽高尺寸
  final double size;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(size * 0.22);

    if (iconPath != null && iconPath!.isNotEmpty) {
      final file = File(iconPath!);
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context, borderRadius),
        ),
      );
    }

    return _buildPlaceholder(context, borderRadius);
  }

  Widget _buildPlaceholder(BuildContext context, BorderRadius borderRadius) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: system
            ? (isDark ? Colors.grey[800] : Colors.grey[200])
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: borderRadius,
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: Center(
        child: Icon(
          system ? Icons.settings : Icons.apps,
          size: size * 0.55,
          color: system
              ? (isDark ? Colors.grey[400] : Colors.grey[700])
              : theme.colorScheme.primary,
        ),
      ),
    );
  }
}
