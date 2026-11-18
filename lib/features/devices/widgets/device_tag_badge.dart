import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

/// 展示用户已有的设备分类标签，列表和设备墙共用原有淡底描边样式。
///
/// [tag] 为用户输入内容，无点击或选择行为；过长时省略并通过 Tooltip 保留全文。
/// 由宿主使用 Wrap 安排多标签，颜色跟随主题主色，不参与设备在线状态判断。
class DeviceTagBadge extends StatelessWidget {
  const DeviceTagBadge({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tag,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: .5),
          borderRadius: AppThemeSizes.radiusSmall,
          border: Border.all(
            color: scheme.primary.withValues(alpha: .2),
            width: AppThemeSizes.borderWidth,
          ),
        ),
        child: Text(
          tag,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            height: 1.4,
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
