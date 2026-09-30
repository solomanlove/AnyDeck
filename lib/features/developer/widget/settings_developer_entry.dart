import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../app/widget/app_toast.dart';
import '../developer_options_screen.dart';

/// 设置页版本号与开发者选项入口复合组件。
///
/// 1. 展示当前软件版本号，并承载“连续点击 5 次激活开发者模式”彩蛋。
/// 2. 当开发者模式已激活时，下方自动浮现“开发者选项”二级菜单入口，点击即可跳转至开发者页面。
/// 3. 保留原有的“检查更新”按钮交互。
class SettingsDeveloperEntry extends ConsumerStatefulWidget {
  /// 创建设置页版本号与开发者选项入口
  ///
  /// [onCheckUpdate] 点击“检查更新”按钮的回调
  /// [brandGreen] 主题高亮绿色，默认 0xff09c47c
  const SettingsDeveloperEntry({
    super.key,
    required this.onCheckUpdate,
    this.brandGreen = const Color(0xff09c47c),
  });

  /// 检查更新回调
  final VoidCallback onCheckUpdate;

  /// 主题品牌绿色
  final Color brandGreen;

  @override
  ConsumerState<SettingsDeveloperEntry> createState() => _SettingsDeveloperEntryState();
}

class _SettingsDeveloperEntryState extends ConsumerState<SettingsDeveloperEntry> {
  /// 连续点击计数
  int _clickCount = 0;

  /// 上次点击时间戳，超过 2 秒未点击重置计数
  DateTime? _lastClickTime;

  /// 处理版本号区域的点击事件
  void _handleVersionTap() {
    final now = DateTime.now();
    // 超过 2 秒未点击则重新开始计数
    if (_lastClickTime == null || now.difference(_lastClickTime!) > const Duration(seconds: 2)) {
      _clickCount = 1;
    } else {
      _clickCount++;
    }
    _lastClickTime = now;

    final isDevMode = ref.read(appSettingsProvider).developerModeEnabled;
    if (isDevMode) {
      AppToast.show(
        context,
        context.l10n.t('developerOptionsAlreadyEnabled'),
        type: AppToastType.info,
      );
      return;
    }

    if (_clickCount >= 5) {
      _clickCount = 0;
      ref.read(appSettingsProvider.notifier).setDeveloperModeEnabled(true);
      // 触发轻微系统触觉反馈（如果支持）
      HapticFeedback.mediumImpact();
      AppToast.show(
        context,
        '🎉 ${context.l10n.t('developerOptionsEnabledTip')}',
        type: AppToastType.success,
      );
    } else if (_clickCount >= 2) {
      final remaining = 5 - _clickCount;
      AppToast.show(
        context,
        context.l10n.t('developerOptionsStepTip').replaceAll('{count}', '$remaining'),
        type: AppToastType.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 版本号行（支持点击彩蛋触发）
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: _handleVersionTap,
          leading: Icon(
            CupertinoIcons.info_circle,
            color: widget.brandGreen,
          ),
          title: Text(context.l10n.t('appVersion')),
          subtitle: const Text('v1.0.0'),
          trailing: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.brandGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            onPressed: widget.onCheckUpdate,
            child: Text(context.l10n.t('checkUpdate')),
          ),
        ),

        // 开发者选项入口（激活后展示）
        if (settings.developerModeEnabled) ...[
          const Divider(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: widget.brandGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                CupertinoIcons.chevron_left_slash_chevron_right,
                color: widget.brandGreen,
                size: 18,
              ),
            ),
            title: Text(
              context.l10n.t('developerOptions'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              context.l10n.t('developerOptionsDesc'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(
              CupertinoIcons.chevron_right,
              size: 16,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DeveloperOptionsScreen(),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
