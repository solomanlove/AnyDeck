part of '../dashboard_screen.dart';

/// 设置页开机自启配置组件与逻辑扩展。
extension _SettingsTabAutoStartActions on _SettingsTab {
  /// 构建开机自启设置项，仅在 macOS 桌面端展示。
  ///
  /// [context]: 构建上下文，用于获取主题与本地化文案。
  /// [ref]: Riverpod 引用，用于监听与调用设置状态。
  /// [brandGreen]: 品牌主绿色，用于保持开关激活色调统一。
  Widget _buildAutoStartSettingRow(
    BuildContext context,
    WidgetRef ref,
    Color brandGreen,
  ) {
    if (!Platform.isMacOS) {
      return const SizedBox.shrink();
    }

    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 24),
        _buildSettingRow(
          context,
          label: context.l10n.t('launchAtStartup'),
          subtitle: context.l10n.t('launchAtStartupDesc'),
          child: Switch.adaptive(
            activeThumbColor: brandGreen,
            activeTrackColor: brandGreen.withValues(alpha: 0.5),
            value: settings.launchAtStartup,
            onChanged: (val) => controller.setLaunchAtStartup(val),
          ),
        ),
        // const Divider(height: 24),
        // _buildSettingRow(
        //   context,
        //   label: context.l10n.t('mainWindowShortcut'),
        //   subtitle: context.l10n.t('mainWindowShortcutDesc'),
        //   child: Row(
        //     mainAxisSize: MainAxisSize.min,
        //     children: ['1', '2', '3', '4', '5'].map((key) {
        //       final isSelected = settings.showWindowShortcutKey == key;
        //       return Padding(
        //         padding: const EdgeInsets.only(left: 6),
        //         child: InkWell(
        //           borderRadius: BorderRadius.circular(8),
        //           onTap: () => controller.setShowWindowShortcut(key),
        //           child: Container(
        //             padding: const EdgeInsets.symmetric(
        //               horizontal: 10,
        //               vertical: 6,
        //             ),
        //             decoration: BoxDecoration(
        //               color: isSelected
        //                   ? brandGreen
        //                   : Theme.of(context).colorScheme.surfaceContainerHighest,
        //               borderRadius: BorderRadius.circular(8),
        //               border: Border.all(
        //                 color: isSelected
        //                     ? brandGreen
        //                     : Theme.of(context).dividerColor.withValues(alpha: 0.3),
        //               ),
        //             ),
        //             child: Text(
        //               '⌘$key',
        //               style: TextStyle(
        //                 fontSize: 12,
        //                 fontWeight: FontWeight.w600,
        //                 color: isSelected
        //                     ? Colors.white
        //                     : Theme.of(context).colorScheme.onSurface,
        //               ),
        //             ),
        //           ),
        //         ),
        //       );
        //     }).toList(),
        //   ),
        // ),
      ],
    );
  }
}
