part of '../dashboard_screen.dart';

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final isZh = context.l10n.locale.languageCode == 'zh';

    // 品牌绿色
    const brandGreen = AppPalette.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardHeaderBar(
          title: context.l10n.t('settings'),
          subtitle: context.l10n.t('settingsDesc'),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 常规设置 (General Settings)
                    _buildSectionCard(
                      context,
                      title: isZh ? '常规' : context.l10n.t('generalSettings'),
                      children: [
                        // 语言选项
                        _buildSettingRow(
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
                        // 外观模式
                        _buildSettingRow(
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
                        // 开机自启 (macOS)
                        _buildAutoStartSettingRow(context, ref, brandGreen),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 软件快捷键集中展示和修改，投屏窗口同步使用相同配置。
                    _buildSectionCard(
                      context,
                      title: context.l10n.t('keyboardShortcuts'),
                      children: const [KeyboardShortcutSettings()],
                    ),
                    const SizedBox(height: 24),

                    // 2. 存储 (Storage Settings)
                    _buildSectionCard(
                      context,
                      title: isZh ? '存储' : 'Storage',
                      children: [
                        // 保存路径
                        _buildSettingRow(
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
                                        .openDirectory(
                                          settings.screenshotSavePath,
                                        );
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
                                    await controller.setScreenshotSavePath(
                                      path,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        // 缓存文件夹
                        _buildCacheSettingRow(context, ref, brandGreen),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 3. 通知与消息设置 (Notification & Message Settings)
                    _buildNotificationSectionCard(context, ref, brandGreen),
                    const SizedBox(height: 24),

                    // 4. 投屏设置 (Screen Mirroring Settings)
                    _buildSectionCard(
                      context,
                      title: context.l10n.t('mirrorSettings'),
                      children: [
                        const MirrorQualityPresets(),
                        _buildSettingRow(
                          context,
                          label: context.l10n.t('mirrorAlwaysOnTop'),
                          subtitle: context.l10n.t('mirrorAlwaysOnTopDesc'),
                          child: CupertinoSwitch(
                            activeTrackColor: const Color(0xFF34C759),
                            value: settings.scrcpyAlwaysOnTop,
                            onChanged: (val) =>
                                controller.setScrcpyAlwaysOnTop(val),
                          ),
                        ),
                        _buildSettingRow(
                          context,
                          label: context.l10n.t('mirrorControlsAlwaysVisible'),
                          subtitle: context.l10n.t(
                            'mirrorControlsAlwaysVisibleDesc',
                          ),
                          child: CupertinoSwitch(
                            activeTrackColor: const Color(0xFF34C759),
                            value: settings.mirrorControlsAlwaysVisible,
                            onChanged: (val) => controller
                                .setMirrorControlsAlwaysVisible(val),
                          ),
                        ),
                        _buildSettingRow(
                          context,
                          label: context.l10n.t('autoPowerOffScreen'),
                          subtitle: context.l10n.t('autoPowerOffScreenDesc'),
                          child: CupertinoSwitch(
                            activeTrackColor: const Color(0xFF34C759),
                            value: settings.autoPowerOffScreen,
                            onChanged: (val) =>
                                controller.setAutoPowerOffScreen(val),
                          ),
                        ),
                        _buildSettingRow(
                          context,
                          label: context.l10n.t('autoIdentifyForegroundApp'),
                          subtitle: context.l10n.t(
                            'autoIdentifyForegroundAppDesc',
                          ),
                          child: CupertinoSwitch(
                            activeTrackColor: const Color(0xFF34C759),
                            value: settings.autoIdentifyForegroundApp,
                            onChanged: (val) =>
                                controller.setAutoIdentifyForegroundApp(val),
                          ),
                        ),
                        _buildSettingRow(
                          context,
                          label: context.l10n.t('autoIdentifyInterval'),
                          subtitle: context.l10n.t('autoIdentifyIntervalDesc'),
                          child: _buildDropdownSelector<int>(
                            context,
                            value: settings.autoIdentifyInterval,
                            items: [1, 2, 3, 5, 10]
                                .map(
                                  (sec) => _DropdownOption(
                                    value: sec,
                                    label: context.l10n
                                        .t('secondsFormat')
                                        .replaceAll('{value}', '$sec'),
                                  ),
                                )
                                .toList(),
                            onChanged: settings.autoIdentifyForegroundApp
                                ? (val) =>
                                      controller.setAutoIdentifyInterval(val)
                                : null,
                          ),
                        ),
                        _buildSettingRow(
                          context,
                          label: context.l10n.t('audioForwarding'),
                          subtitle: context.l10n.t('audioForwardingDesc'),
                          child: CupertinoSwitch(
                            activeTrackColor: const Color(0xFF34C759),
                            value: settings.mirrorAudioEnabled,
                            onChanged: (val) =>
                                controller.setMirrorAudioEnabled(val),
                          ),
                        ),
                        _buildSettingRow(
                          context,
                          label: context.l10n.t('iosAudioForwarding'),
                          subtitle: context.l10n.t('iosAudioForwardingDesc'),
                          child: CupertinoSwitch(
                            activeTrackColor: const Color(0xFF34C759),
                            value: settings.iosMirrorAudioEnabled,
                            onChanged: (val) =>
                                controller.setIosMirrorAudioEnabled(val),
                          ),
                        ),
                        _buildSettingRow(
                          context,
                          label: context.l10n.t('iosAirplayName'),
                          subtitle: context.l10n.t('iosAirplayNameDesc'),
                          child: ReceiverNameSettingField(
                            value: settings.airplayServerName,
                            defaultName: AppSettings.defaultAirplayServerName,
                            resetTooltip: context.l10n.t('iosAirplayNameReset'),
                            onChanged: (val) =>
                                controller.setAirplayServerName(val),
                            onApplied: restartAirplayBroadcastIfIdle,
                          ),
                        ),
                        _buildSettingRow(
                          context,
                          label: context.l10n.t('androidDlnaName'),
                          subtitle: context.l10n.t('androidDlnaNameDesc'),
                          child: ReceiverNameSettingField(
                            value: settings.dlnaServerName,
                            defaultName: AppSettings.defaultDlnaServerName,
                            resetTooltip: context.l10n.t('androidDlnaNameReset'),
                            onChanged: (val) => controller.setDlnaServerName(val),
                          ),
                        ),
                        _buildSettingRow(
                          context,
                          label: context.l10n.t('videoBitrate'),
                          subtitle: context.l10n.t('videoBitrateDesc'),
                          child: _buildDropdownSelector<int>(
                            context,
                            value: settings.mirrorVideoBitrate,
                            items: const [
                              _DropdownOption(
                                value: 2000000,
                                label: '2 Mbps',
                              ),
                              _DropdownOption(
                                value: 4000000,
                                label: '4 Mbps',
                              ),
                              _DropdownOption(
                                value: 8000000,
                                label: '8 Mbps',
                              ),
                              _DropdownOption(
                                value: 16000000,
                                label: '16 Mbps',
                              ),
                              _DropdownOption(
                                value: 32000000,
                                label: '32 Mbps',
                              ),
                            ],
                            onChanged: (val) =>
                                controller.setMirrorVideoBitrate(val),
                          ),
                        ),
                        _buildSettingRow(
                          context,
                          label: context.l10n.t('maxResolution'),
                          subtitle: context.l10n.t('maxResolutionDesc'),
                          child: _buildDropdownSelector<int>(
                            context,
                            value: settings.mirrorMaxSize,
                            items: [
                              _DropdownOption(
                                value: 0,
                                label: context.l10n.t('originalUnlimited'),
                              ),
                              const _DropdownOption(
                                value: 720,
                                label: '720 px',
                              ),
                              const _DropdownOption(
                                value: 1080,
                                label: '1080 px',
                              ),
                              const _DropdownOption(
                                value: 1440,
                                label: '1440 px',
                              ),
                              const _DropdownOption(
                                value: 1920,
                                label: '1920 px',
                              ),
                            ],
                            onChanged: (val) =>
                                controller.setMirrorMaxSize(val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 5. 录屏设置 (Screen Recording Settings)
                    _buildSectionCard(
                      context,
                      title: isZh ? '录屏设置' : 'Screen Recording Settings',
                      children: [
                        _buildSettingRow(
                          context,
                          label: isZh ? '强制电脑本地录制' : 'Force PC Local Recording',
                          subtitle: isZh
                              ? '默认采用动态决策（根据设备自动选择最佳方式）；开启后将强制使用电脑端 scrcpy 进行本地录制。'
                              : 'Use dynamic decision by default. Enable to force host-side recording using scrcpy.',
                          child: CupertinoSwitch(
                            activeTrackColor: const Color(0xFF34C759),
                            value: settings.forceHostRecording,
                            onChanged: (val) =>
                                controller.setForceHostRecording(val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 6. 关于与支持 (About & Support)
                    _buildSectionCard(
                      context,
                      title: context.l10n.t('aboutAndSupport'),
                      children: [
                        // 行自身负责内容内边距，让 Hover 覆盖到卡片边缘与分割线。
                        SettingsDeveloperEntry(
                          brandGreen: brandGreen,
                          onCheckUpdate: () => showDialog<void>(
                            context: context,
                            builder: (_) => const _UpdateCheckDialog(),
                          ),
                        ),
                        const SettingsFeedbackEntry(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
