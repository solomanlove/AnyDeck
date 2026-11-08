part of '../dashboard_screen.dart';

/// 常规、快捷键、通知、存储与支持的展示目录；不承担持久化逻辑。
extension _SettingsTabCatalog on _SettingsTab {
  List<SettingsItem> _catalogItems(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final isZh = context.l10n.locale.languageCode == 'zh';
    return [
      SettingsItem(
        id: 'language',
        category: SettingsCategory.general,
        section: context.l10n.t('generalSettings'),
        title: context.l10n.t('language'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('language'),
          child: _buildDropdownSelector<AppLanguage>(
            context,
            alignMenu: true,
            value: settings.language,
            items: [
              _DropdownOption(
                value: AppLanguage.zh,
                label: isZh ? '简体中文' : context.l10n.t('chinese'),
              ),
              _DropdownOption(
                value: AppLanguage.en,
                label: context.l10n.t('english'),
              ),
            ],
            onChanged: (lang) => controller.setLanguage(lang),
          ),
        ),
      ),
      SettingsItem(
        id: 'theme',
        category: SettingsCategory.general,
        section: context.l10n.t('generalSettings'),
        title: context.l10n.t('theme'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('theme'),
          child: _buildDropdownSelector<ThemeMode>(
            context,
            alignMenu: true,
            value: settings.themeMode,
            items: [
              _DropdownOption(
                value: ThemeMode.light,
                label: context.l10n.t('themeLight'),
              ),
              _DropdownOption(
                value: ThemeMode.dark,
                label: context.l10n.t('themeDark'),
              ),
              _DropdownOption(
                value: ThemeMode.system,
                label: context.l10n.t('themeSystem'),
              ),
            ],
            onChanged: (mode) => controller.setThemeMode(mode),
          ),
        ),
      ),
      if (Platform.isMacOS)
        SettingsItem(
          id: 'launchAtStartup',
          category: SettingsCategory.general,
          section: context.l10n.t('settingsStartup'),
          title: context.l10n.t('launchAtStartup'),
          description: context.l10n.t('launchAtStartupDesc'),
          child: _buildAutoStartSettingRow(context, ref, AppPalette.primary),
        ),
      SettingsItem(
        id: 'keyboardShortcuts',
        category: SettingsCategory.shortcuts,
        section: context.l10n.t('keyboardShortcuts'),
        title: context.l10n.t('keyboardShortcuts'),
        keywords: [
          context.l10n.t('settingsShortcutKeywords'),
          settings.mainWindowBinding.label(),
          for (final action in WindowShortcut.values)
            settings.windowShortcuts.bindingFor(action).label(),
          for (final action in MirrorShortcut.values)
            settings.mirrorShortcuts.bindingFor(action).label(),
        ].join(' '),
        description: context.l10n.t('shortcutMirrorHint'),
        searchLabels: [
          context.l10n.t('mainWindowShortcut'),
          for (final action in WindowShortcut.values)
            context.l10n.t(action.labelKey),
          for (final action in MirrorShortcut.values)
            context.l10n.t(action.labelKey),
        ],
        child: const KeyboardShortcutSettings(),
      ),
      SettingsItem(
        id: 'notifications',
        category: SettingsCategory.notifications,
        section: context.l10n.t('notificationSettingsTitle'),
        title: context.l10n.t('notificationSettingsTitle'),
        keywords: context.l10n.t('settingsNotificationKeywords'),
        description: [
          for (final key in [
            'deviceConnectNotificationDesc',
            'notificationBodyPreviewDesc',
            'notificationPermissionDesc',
          ])
            context.l10n.t(key),
        ].join(' '),
        searchLabels: [
          for (final key in [
            'deviceConnectNotification',
            'notificationBodyPreview',
            'notificationPermission',
          ])
            context.l10n.t(key),
        ],
        standalone: true,
        child: _buildNotificationSectionCard(context, ref, AppPalette.primary),
      ),
      SettingsItem(
        id: 'saveDirectory',
        category: SettingsCategory.storage,
        section: context.l10n.t('settingsFiles'),
        title: context.l10n.t('saveDirectory'),
        keywords: context.l10n.t('settingsFileKeywords'),
        description: settings.screenshotSavePath.isEmpty
            ? context.l10n.t('notSetDefaultPath')
            : settings.screenshotSavePath,
        child: _buildSettingRow(
          context,
          label: context.l10n.t('saveDirectory'),
          subtitle: settings.screenshotSavePath.isEmpty
              ? context.l10n.t('notSetDefaultPath')
              : settings.screenshotSavePath,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settings.screenshotSavePath.isNotEmpty) ...[
                _buildTextActionButton(
                  text: isZh ? '打开' : 'Open',
                  color: const Color(0xFF2563EB),
                  onTap: () {
                    ref
                        .read(hostPlatformServiceProvider)
                        .openDirectory(settings.screenshotSavePath);
                  },
                ),
                const SizedBox(width: 16),
              ],
              _buildTextActionButton(
                text: isZh ? '更改' : 'Change',
                color: const Color(0xFF2563EB),
                onTap: () async {
                  final path = await getDirectoryPath();
                  if (path != null) {
                    await controller.setScreenshotSavePath(path);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      SettingsItem(
        id: 'cacheFolders',
        category: SettingsCategory.storage,
        section: context.l10n.t('settingsCache'),
        title: context.l10n.t('cacheFolders'),
        description: context.l10n.t('cacheFoldersDesc'),
        keywords: context.l10n.t('settingsStorageKeywords'),
        child: _buildCacheSettingRow(context, ref, AppPalette.primary),
      ),
      SettingsItem(
        id: 'appVersion',
        category: SettingsCategory.about,
        section: context.l10n.t('aboutAndSupport'),
        title: context.l10n.t('appVersion'),
        searchLabels: [
          context.l10n.t('checkUpdate'),
          if (settings.developerModeEnabled) context.l10n.t('developerOptions'),
        ],
        child: SettingsDeveloperEntry(
          brandGreen: AppPalette.primary,
          onCheckUpdate: () => showDialog<void>(
            context: context,
            builder: (_) => const _UpdateCheckDialog(),
          ),
        ),
      ),
      SettingsItem(
        id: 'feedback',
        category: SettingsCategory.about,
        section: context.l10n.t('aboutAndSupport'),
        title: context.l10n.t('settingsFeedback'),
        child: const SettingsFeedbackEntry(),
      ),
    ];
  }
}
