part of '../dashboard_screen.dart';

/// 投屏、录制与接收分类；沿用原有设置回调和协议重启规则。
extension _SettingsTabMedia on _SettingsTab {
  List<SettingsItem> _mediaItems(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    return [
      SettingsItem(
        id: 'mirrorPresetTitle',
        category: SettingsCategory.mirroring,
        section: context.l10n.t('settingsQuality'),
        title: context.l10n.t('mirrorPresetTitle'),
        keywords: context.l10n.t('settingsQualityKeywords'),
        child: const MirrorQualityPresets(),
      ),
      SettingsItem(
        id: 'mirrorAlwaysOnTop',
        category: SettingsCategory.mirroring,
        section: context.l10n.t('settingsWindowControl'),
        title: context.l10n.t('mirrorAlwaysOnTop'),
        description: context.l10n.t('mirrorAlwaysOnTopDesc'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('mirrorAlwaysOnTop'),
          subtitle: context.l10n.t('mirrorAlwaysOnTopDesc'),
          child: CupertinoSwitch(
            activeTrackColor: const Color(0xFF34C759),
            value: settings.scrcpyAlwaysOnTop,
            onChanged: (val) => controller.setScrcpyAlwaysOnTop(val),
          ),
        ),
      ),
      SettingsItem(
        id: 'mirrorControlsAlwaysVisible',
        category: SettingsCategory.mirroring,
        section: context.l10n.t('settingsWindowControl'),
        title: context.l10n.t('mirrorControlsAlwaysVisible'),
        description: context.l10n.t('mirrorControlsAlwaysVisibleDesc'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('mirrorControlsAlwaysVisible'),
          subtitle: context.l10n.t('mirrorControlsAlwaysVisibleDesc'),
          child: CupertinoSwitch(
            activeTrackColor: const Color(0xFF34C759),
            value: settings.mirrorControlsAlwaysVisible,
            onChanged: (val) => controller.setMirrorControlsAlwaysVisible(val),
          ),
        ),
      ),
      SettingsItem(
        id: 'autoPowerOffScreen',
        category: SettingsCategory.mirroring,
        section: context.l10n.t('settingsWindowControl'),
        title: context.l10n.t('autoPowerOffScreen'),
        description: context.l10n.t('autoPowerOffScreenDesc'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('autoPowerOffScreen'),
          subtitle: context.l10n.t('autoPowerOffScreenDesc'),
          child: CupertinoSwitch(
            activeTrackColor: const Color(0xFF34C759),
            value: settings.autoPowerOffScreen,
            onChanged: (val) => controller.setAutoPowerOffScreen(val),
          ),
        ),
      ),
      SettingsItem(
        id: 'autoIdentifyForegroundApp',
        category: SettingsCategory.mirroring,
        section: context.l10n.t('settingsWindowControl'),
        title: context.l10n.t('autoIdentifyForegroundApp'),
        description: context.l10n.t('autoIdentifyForegroundAppDesc'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('autoIdentifyForegroundApp'),
          subtitle: context.l10n.t('autoIdentifyForegroundAppDesc'),
          child: CupertinoSwitch(
            activeTrackColor: const Color(0xFF34C759),
            value: settings.autoIdentifyForegroundApp,
            onChanged: (val) => controller.setAutoIdentifyForegroundApp(val),
          ),
        ),
      ),
      SettingsItem(
        id: 'autoIdentifyInterval',
        category: SettingsCategory.mirroring,
        section: context.l10n.t('settingsWindowControl'),
        title: context.l10n.t('autoIdentifyInterval'),
        description: context.l10n.t('autoIdentifyIntervalDesc'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('autoIdentifyInterval'),
          subtitle: context.l10n.t('autoIdentifyIntervalDesc'),
          child: _buildDropdownSelector<int>(
            context,
            alignMenu: true,
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
                ? (val) => controller.setAutoIdentifyInterval(val)
                : null,
          ),
        ),
      ),
      SettingsItem(
        id: 'audioForwarding',
        category: SettingsCategory.mirroring,
        section: context.l10n.t('settingsAudio'),
        title: context.l10n.t('audioForwarding'),
        description: context.l10n.t('audioForwardingDesc'),
        keywords: context.l10n.t('settingsAudioKeywords'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('audioForwarding'),
          subtitle: context.l10n.t('audioForwardingDesc'),
          child: CupertinoSwitch(
            activeTrackColor: const Color(0xFF34C759),
            value: settings.mirrorAudioEnabled,
            onChanged: (val) => controller.setMirrorAudioEnabled(val),
          ),
        ),
      ),
      SettingsItem(
        id: 'iosAudioForwarding',
        category: SettingsCategory.mirroring,
        section: context.l10n.t('settingsAudio'),
        title: context.l10n.t('iosAudioForwarding'),
        description: context.l10n.t('iosAudioForwardingDesc'),
        keywords: context.l10n.t('settingsAudioKeywords'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('iosAudioForwarding'),
          subtitle: context.l10n.t('iosAudioForwardingDesc'),
          child: CupertinoSwitch(
            activeTrackColor: const Color(0xFF34C759),
            value: settings.iosMirrorAudioEnabled,
            onChanged: (val) => controller.setIosMirrorAudioEnabled(val),
          ),
        ),
      ),
      SettingsItem(
        id: 'videoBitrate',
        category: SettingsCategory.mirroring,
        section: context.l10n.t('settingsQuality'),
        title: context.l10n.t('videoBitrate'),
        description: context.l10n.t('videoBitrateDesc'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('videoBitrate'),
          subtitle: context.l10n.t('videoBitrateDesc'),
          child: _buildDropdownSelector<int>(
            context,
            alignMenu: true,
            value: settings.mirrorVideoBitrate,
            items: const [
              _DropdownOption(value: 2000000, label: '2 Mbps'),
              _DropdownOption(value: 4000000, label: '4 Mbps'),
              _DropdownOption(value: 8000000, label: '8 Mbps'),
              _DropdownOption(value: 16000000, label: '16 Mbps'),
              _DropdownOption(value: 32000000, label: '32 Mbps'),
            ],
            onChanged: (val) => controller.setMirrorVideoBitrate(val),
          ),
        ),
      ),
      SettingsItem(
        id: 'maxResolution',
        category: SettingsCategory.mirroring,
        section: context.l10n.t('settingsQuality'),
        title: context.l10n.t('maxResolution'),
        description: context.l10n.t('maxResolutionDesc'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('maxResolution'),
          subtitle: context.l10n.t('maxResolutionDesc'),
          child: _buildDropdownSelector<int>(
            context,
            alignMenu: true,
            value: settings.mirrorMaxSize,
            items: [
              _DropdownOption(
                value: 0,
                label: context.l10n.t('originalUnlimited'),
              ),
              const _DropdownOption(value: 720, label: '720 px'),
              const _DropdownOption(value: 1080, label: '1080 px'),
              const _DropdownOption(value: 1440, label: '1440 px'),
              const _DropdownOption(value: 1920, label: '1920 px'),
            ],
            onChanged: (val) => controller.setMirrorMaxSize(val),
          ),
        ),
      ),
      SettingsItem(
        id: 'forceHostRecording',
        category: SettingsCategory.mirroring,
        section: context.l10n.t('settingsRecording'),
        title: context.l10n.t('settingsForceHostRecording'),
        description: context.l10n.t('settingsForceHostRecordingDesc'),
        child: _buildSettingRow(
          context,
          label: context.l10n.t('settingsForceHostRecording'),
          subtitle: context.l10n.t('settingsForceHostRecordingDesc'),
          child: CupertinoSwitch(
            activeTrackColor: const Color(0xFF34C759),
            value: settings.forceHostRecording,
            onChanged: (val) => controller.setForceHostRecording(val),
          ),
        ),
      ),
      SettingsItem(
        id: 'iosAirplayName',
        category: SettingsCategory.receivers,
        section: context.l10n.t('settingsAirplay'),
        title: context.l10n.t('iosAirplayName'),
        description: context.l10n.t('iosAirplayNameDesc'),
        keywords: '${context.l10n.t('settingsReceiverKeywords')} AirPlay',
        child: _buildSettingRow(
          context,
          label: context.l10n.t('iosAirplayName'),
          subtitle: context.l10n.t('iosAirplayNameDesc'),
          child: ReceiverNameSettingField(
            value: settings.airplayServerName,
            defaultName: AppSettings.defaultAirplayServerName,
            resetTooltip: context.l10n.t('iosAirplayNameReset'),
            onChanged: (val) => controller.setAirplayServerName(val),
            onApplied: restartAirplayBroadcastIfIdle,
          ),
        ),
      ),
      SettingsItem(
        id: 'androidDlnaName',
        category: SettingsCategory.receivers,
        section: context.l10n.t('settingsDlna'),
        title: context.l10n.t('androidDlnaName'),
        description: context.l10n.t('androidDlnaNameDesc'),
        keywords: '${context.l10n.t('settingsReceiverKeywords')} DLNA',
        child: _buildSettingRow(
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
      ),
    ];
  }
}
