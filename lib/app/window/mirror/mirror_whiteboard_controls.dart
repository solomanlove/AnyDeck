import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../../features/control/whiteboard/mirror_whiteboard_controller.dart';
import 'mirror_toolbar_button.dart';

/// 投屏工具栏的白板入口和颜色、撤销、清空操作。
/// controller 属于当前窗口，点击画笔后才展示其余三个操作。
/// 用法：放入投屏右侧工具栏，并与视频画布共享同一个 controller。
class MirrorWhiteboardControls extends StatelessWidget {
  const MirrorWhiteboardControls({super.key, required this.controller});

  /// 当前窗口的白板状态；用于切换绘制、颜色和笔迹历史。
  final MirrorWhiteboardController controller;

  static const colors = <(Color, String)>[
    (Colors.red, 'screenshotEditColorRed'),
    (Colors.yellow, 'screenshotEditColorYellow'),
    (Colors.green, 'screenshotEditColorGreen'),
    (Colors.blue, 'screenshotEditColorBlue'),
    (Colors.black, 'screenshotEditColorBlack'),
    (Colors.white, 'screenshotEditColorWhite'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MirrorToolbarButton(
            key: const ValueKey('mirror-whiteboard-toggle'),
            shortcut: MirrorShortcut.whiteboard,
            icon: Icon(
              CupertinoIcons.paintbrush,
              color: controller.active
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: context.l10n.t(
              controller.active
                  ? 'mirrorWhiteboardClose'
                  : 'mirrorWhiteboardOpen',
            ),
            onPressed: controller.toggle,
          ),
          if (controller.active) ...[
            PopupMenuButton<Color>(
              key: const ValueKey('mirror-whiteboard-color'),
              tooltip: context.l10n.t('mirrorWhiteboardColor'),
              onSelected: controller.setColor,
              itemBuilder: (context) => [
                for (final (color, label) in colors)
                  PopupMenuItem<Color>(
                    value: color,
                    child: Row(
                      children: [
                        Icon(Icons.circle, color: color, size: 18),
                        const SizedBox(width: 8),
                        Text(context.l10n.t(label)),
                      ],
                    ),
                  ),
              ],
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: Icon(
                    Icons.color_lens_outlined,
                    size: 20,
                    color: controller.color,
                  ),
                ),
              ),
            ),
            MirrorToolbarButton(
              key: const ValueKey('mirror-whiteboard-undo'),
              icon: const Icon(CupertinoIcons.arrow_uturn_left),
              tooltip: context.l10n.t('screenshotEditUndo'),
              onPressed: controller.canUndo ? controller.undo : null,
            ),
            MirrorToolbarButton(
              key: const ValueKey('mirror-whiteboard-clear'),
              icon: const Icon(CupertinoIcons.clear),
              tooltip: context.l10n.t('mirrorWhiteboardClear'),
              onPressed: controller.canUndo ? controller.clear : null,
            ),
          ],
        ],
      ),
    );
  }
}
