import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../model/screenshot_state.dart';

/// 截图工作区底栏，供 Android、iOS 和 HarmonyOS 页面复用。
/// 放在页面 Column 的 Expanded 画布之后：state 提供图片信息与录屏禁用状态，
/// 四个回调连接现有画布的放大、缩小、原始比例及重置操作。
class ScreenshotBottomBar extends StatelessWidget {
  const ScreenshotBottomBar({
    super.key,
    required this.state,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoom1To1,
    required this.onZoomReset,
  });

  final ScreenshotLayoutState state;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoom1To1;
  final VoidCallback onZoomReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = state.hasImage && !state.isRecordingActive;
    final imageInfo =
        '${state.imgWidth}x${state.imgHeight} PNG ${state.sizeLabel}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 窄窗口可横向滚动按钮，图片信息保留 Tooltip 并允许省略显示。
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _zoomButton(
                    context,
                    CupertinoIcons.zoom_in,
                    'zoomIn',
                    enabled ? onZoomIn : null,
                  ),
                  _zoomButton(
                    context,
                    CupertinoIcons.zoom_out,
                    'zoomOut',
                    enabled ? onZoomOut : null,
                  ),
                  Tooltip(
                    message: context.l10n.t('zoom1to1'),
                    child: InkWell(
                      onTap: enabled ? onZoom1To1 : null,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: enabled
                                ? colors.outline
                                : theme.disabledColor,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '1:1',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: enabled
                                ? colors.onSurfaceVariant
                                : theme.disabledColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _zoomButton(
                    context,
                    CupertinoIcons.arrow_counterclockwise,
                    'zoomReset',
                    enabled ? onZoomReset : null,
                  ),
                ],
              ),
            ),
          ),
          if (state.hasImage) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Tooltip(
                message: imageInfo,
                child: Text(
                  imageInfo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _zoomButton(
    BuildContext context,
    IconData icon,
    String tooltipKey,
    VoidCallback? onPressed,
  ) => IconButton(
    icon: Icon(icon, size: 20),
    tooltip: context.l10n.t(tooltipKey),
    onPressed: onPressed,
    style: IconButton.styleFrom(
      padding: const EdgeInsets.all(6),
      minimumSize: const Size(32, 32),
    ),
  );
}
