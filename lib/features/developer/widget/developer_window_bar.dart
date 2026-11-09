import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/window/model/desktop_chrome_policy.dart';
import '../../../app/window/widget/desktop_workspace_surface.dart';

/// 开发者页面的窗口导航栏，仅保留返回设置入口；空白区域支持拖动窗口。
/// 使用桌面公共表面与平台按钮避让规则，可直接放在页面内容上方。
class DeveloperWindowBar extends StatelessWidget {
  const DeveloperWindowBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DesktopWorkspaceSurface(
      child: Container(
        key: const ValueKey('developer-window-bar'),
        height: 56,
        padding: EdgeInsets.only(
          left: DesktopChromePolicy.current.usesMacChrome ? 88 : 20,
          right: 24,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            TextButton.icon(
              key: const ValueKey('developer-back-settings'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(CupertinoIcons.chevron_back, size: 16),
              label: Text(context.l10n.t('settings')),
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurface,
                backgroundColor: colors.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                textStyle: Theme.of(context).textTheme.labelLarge,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: colors.outlineVariant),
                ),
              ),
            ),
            const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
          ],
        ),
      ),
    );
  }
}
