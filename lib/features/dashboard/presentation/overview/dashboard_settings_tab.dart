part of '../dashboard_screen.dart';

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final theme = Theme.of(context);

    // Primary brand green
    const brandGreen = Color(0xff09c47c);

    final isEn = context.l10n.t('languageCode') == 'en';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header section
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: brandGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        CupertinoIcons.settings_solid,
                        color: brandGreen,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.t('settings'),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isEn
                                ? 'Manage application preferences and configurations'
                                : '管理应用全局配置和偏好设置',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Card 1: 常规设置 (General Settings)
                _buildSectionCard(
                  context,
                  title: isEn ? 'General Settings' : '常规设置',
                  icon: CupertinoIcons.circle_grid_hex,
                  children: [
                    // Language option selector
                    _buildSettingRow(
                      context,
                      label: context.l10n.t('language'),
                      subtitle: isEn
                          ? 'Choose application language'
                          : '选择应用显示语言',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildOptionButton(
                            context,
                            label: context.l10n.t('chinese'),
                            selected: settings.language == AppLanguage.zh,
                            onTap: () => controller.setLanguage(AppLanguage.zh),
                          ),
                          const SizedBox(width: 8),
                          _buildOptionButton(
                            context,
                            label: context.l10n.t('english'),
                            selected: settings.language == AppLanguage.en,
                            onTap: () => controller.setLanguage(AppLanguage.en),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 24),
                    // Theme option selector
                    _buildSettingRow(
                      context,
                      label: context.l10n.t('theme'),
                      subtitle: isEn
                          ? 'Select interface theme mode'
                          : '选择界面主题模式',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildOptionButton(
                            context,
                            label: context.l10n.t('themeSystem'),
                            selected: settings.themeMode == ThemeMode.system,
                            icon: CupertinoIcons.desktopcomputer,
                            onTap: () =>
                                controller.setThemeMode(ThemeMode.system),
                          ),
                          const SizedBox(width: 8),
                          _buildOptionButton(
                            context,
                            label: context.l10n.t('themeLight'),
                            selected: settings.themeMode == ThemeMode.light,
                            icon: CupertinoIcons.sun_max,
                            onTap: () =>
                                controller.setThemeMode(ThemeMode.light),
                          ),
                          const SizedBox(width: 8),
                          _buildOptionButton(
                            context,
                            label: context.l10n.t('themeDark'),
                            selected: settings.themeMode == ThemeMode.dark,
                            icon: CupertinoIcons.moon,
                            onTap: () =>
                                controller.setThemeMode(ThemeMode.dark),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Card 2: 投屏设置 (Screen Mirroring Settings)
                _buildSectionCard(
                  context,
                  title: isEn ? 'Screen Mirroring Settings' : '投屏设置',
                  icon: CupertinoIcons.device_phone_portrait,
                  children: [
                    _buildSettingRow(
                      context,
                      label: isEn ? 'Always on Top' : '投屏窗口最前',
                      subtitle: isEn
                          ? 'Keep mirroring window on top of others'
                          : '保持投屏窗口置顶显示',
                      child: Switch.adaptive(
                        activeThumbColor: brandGreen,
                        activeTrackColor: brandGreen.withValues(alpha: 0.5),
                        value: settings.scrcpyAlwaysOnTop,
                        onChanged: (val) =>
                            controller.setScrcpyAlwaysOnTop(val),
                      ),
                    ),
                    const Divider(height: 24),
                    _buildSettingRow(
                      context,
                      label: isEn ? 'Audio Forwarding' : '音频转发',
                      subtitle: isEn
                          ? 'Forward android audio to computer speakers'
                          : '将安卓设备音频转发到电脑扬声器',
                      child: Switch.adaptive(
                        activeThumbColor: brandGreen,
                        activeTrackColor: brandGreen.withValues(alpha: 0.5),
                        value: settings.mirrorAudioEnabled,
                        onChanged: (val) =>
                            controller.setMirrorAudioEnabled(val),
                      ),
                    ),
                    const Divider(height: 24),
                    _buildSettingRow(
                      context,
                      label: isEn ? 'Video Bitrate' : '传输码率',
                      subtitle: isEn
                          ? 'Adjust mirroring video quality'
                          : '调整投屏视频传输码率品质',
                      child: DropdownButton<int>(
                        value: settings.mirrorVideoBitrate,
                        underline: const SizedBox.shrink(),
                        icon: const Icon(CupertinoIcons.chevron_down, size: 16),
                        items: const [
                          DropdownMenuItem(
                            value: 2000000,
                            child: Text('2 Mbps'),
                          ),
                          DropdownMenuItem(
                            value: 4000000,
                            child: Text('4 Mbps'),
                          ),
                          DropdownMenuItem(
                            value: 8000000,
                            child: Text('8 Mbps'),
                          ),
                          DropdownMenuItem(
                            value: 16000000,
                            child: Text('16 Mbps'),
                          ),
                          DropdownMenuItem(
                            value: 32000000,
                            child: Text('32 Mbps'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            controller.setMirrorVideoBitrate(val);
                          }
                        },
                      ),
                    ),
                    const Divider(height: 24),
                    _buildSettingRow(
                      context,
                      label: isEn ? 'Max Resolution' : '最大分辨率限制',
                      subtitle: isEn
                          ? 'Limit maximum projection resolution'
                          : '限制投屏的最大分辨率高度',
                      child: DropdownButton<int>(
                        value: settings.mirrorMaxSize,
                        underline: const SizedBox.shrink(),
                        icon: const Icon(CupertinoIcons.chevron_down, size: 16),
                        items: const [
                          DropdownMenuItem(
                            value: 0,
                            child: Text('Original / 无限制'),
                          ),
                          DropdownMenuItem(value: 720, child: Text('720p')),
                          DropdownMenuItem(value: 1080, child: Text('1080p')),
                          DropdownMenuItem(value: 1440, child: Text('1440p')),
                          DropdownMenuItem(value: 1920, child: Text('1920p')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            controller.setMirrorMaxSize(val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Card 3: 关于与支持 (About & Support)
                _buildSectionCard(
                  context,
                  title: isEn ? 'About & Info' : '关于与说明',
                  icon: CupertinoIcons.info_circle,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        CupertinoIcons.person,
                        color: brandGreen,
                      ),
                      title: Text(context.l10n.t('authorInfo')),
                      trailing: const Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                      ),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => const _AuthorInfoDialog(),
                      ),
                    ),
                    const Divider(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        CupertinoIcons.book,
                        color: brandGreen,
                      ),
                      title: Text(context.l10n.t('softwareManual')),
                      trailing: const Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                      ),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => const _SoftwareManualDialog(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xff09c47c), size: 20),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow(
    BuildContext context, {
    required String label,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        child,
      ],
    );
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const brandGreen = Color(0xff09c47c);
    final outlineColor = selected
        ? brandGreen
        : (isDark ? const Color(0xff334155) : const Color(0xffe2e8f0));
    final textColor = selected
        ? brandGreen
        : (isDark ? Colors.white70 : const Color(0xff5f6b6e));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? brandGreen.withValues(alpha: 0.1)
                : Colors.transparent,
            border: Border.all(color: outlineColor, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: textColor),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
