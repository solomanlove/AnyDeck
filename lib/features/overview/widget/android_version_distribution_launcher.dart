import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/window/multi_window_compat.dart';
import '../model/platform_distribution_type.dart';
import 'platform_version_distribution_shell_view.dart';

/// 打开平台与 API 版本分布独立 macOS 窗口，若环境不支持则优雅降级为居中弹窗。
Future<void> openAndroidVersionDistributionWindow(
  BuildContext context, {
  String? currentVersion,
  PlatformDistributionType platform = PlatformDistributionType.android,
}) async {
  final windowTitle = context.l10n.t(platform.titleL10nKey);

  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    showAndroidVersionDistributionDialog(
      context,
      currentVersion: currentVersion,
      platform: platform,
    );
    return;
  }

  try {
    await createAdbManageWindow(
      arguments: {
        'type': 'version_distribution',
        'initialVersion': currentVersion,
        'platform': platform.id,
      },
      frame: const Offset(140, 120) & const Size(980, 640),
      title: windowTitle,
    );
  } catch (e) {
    debugPrint('Failed to open version distribution window, fallback to dialog: $e');
    if (context.mounted) {
      showAndroidVersionDistributionDialog(
        context,
        currentVersion: currentVersion,
        platform: platform,
      );
    }
  }
}

/// 降级在主窗口内以悬浮模态弹窗展示分布视图。
void showAndroidVersionDistributionDialog(
  BuildContext context, {
  String? currentVersion,
  PlatformDistributionType platform = PlatformDistributionType.android,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 980,
            maxHeight: 640,
          ),
          child: PlatformVersionDistributionShellView(
            isStandaloneWindow: false,
            initialPlatform: platform,
            initialVersion: currentVersion,
            onClose: () => Navigator.of(ctx).pop(),
          ),
        ),
      );
    },
  );
}

/// 主页系统版本卡片右上角的新版 info 图标交互组件。
/// 点击打开独立 macOS 窗口，悬浮展示指引提示。
class AndroidVersionInfoIcon extends StatelessWidget {
  const AndroidVersionInfoIcon({
    super.key,
    this.currentVersion,
    this.platform = PlatformDistributionType.android,
  });

  final String? currentVersion;
  final PlatformDistributionType platform;

  @override
  Widget build(BuildContext context) {
    final tooltipText = context.l10n.t(
      platform == PlatformDistributionType.harmony
          ? 'harmonyApiDistributionTooltip'
          : 'androidApiDistributionTooltip',
    );

    return Tooltip(
      message: tooltipText.isNotEmpty
          ? tooltipText
          : 'Android Platform/API Version Distribution (点击在新窗口中打开)',
      preferBelow: false,
      verticalOffset: 16,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openAndroidVersionDistributionWindow(
            context,
            currentVersion: currentVersion,
            platform: platform,
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              CupertinoIcons.info_circle,
              size: 17,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
