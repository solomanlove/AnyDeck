import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/settings/app_settings.dart';
import '../../app/settings/app_settings_controller.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widget/app_toast.dart';
import '../../core/airplay/airplay_server_service.dart';
import '../../core/airplay/airplay_server_state.dart';
import '../../core/dlna/dlna_renderer_service.dart';
import '../../core/providers/app_providers.dart';
import '../airplay/airplay_mirror_target.dart';
import '../overview/widget/receiver_name_setting_field.dart';
import '../widgets/dashboard_header_bar.dart';
import 'widgets/receiver_app_support_guide.dart';
import 'widgets/receiver_service_card.dart';

/// 主窗口统一投屏接收管理页，集中管理 AirPlay 屏幕镜像与 DLNA 视频接收。
class ReceiverDashboardTab extends StatelessWidget {
  const ReceiverDashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DashboardHeaderBar(
          title: context.l10n.t('receiverCenter'),
          subtitle: context.l10n.t('receiverCenterDesc'),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cards = <Widget>[
                  const AirPlayReceiverCard(),
                  const DlnaReceiverCard(),
                ];
                final serviceCards = constraints.maxWidth < 860
                    ? Column(
                        children: [
                          cards.first,
                          const SizedBox(height: 16),
                          cards.last,
                        ],
                      )
                    // 仅双列按最高卡片拉伸，单列保留内容自然高度。
                    : IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: cards.first),
                            const SizedBox(width: 16),
                            Expanded(child: cards.last),
                          ],
                        ),
                      );
                return Column(
                  children: [
                    serviceCards,
                    const SizedBox(height: 16),
                    const ReceiverAppSupportGuide(),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// AirPlay 广播状态、接收端名称与活跃投屏窗口入口。
class AirPlayReceiverCard extends ConsumerStatefulWidget {
  const AirPlayReceiverCard({super.key});

  @override
  ConsumerState<AirPlayReceiverCard> createState() =>
      _AirPlayReceiverCardState();
}

class _AirPlayReceiverCardState extends ConsumerState<AirPlayReceiverCard> {
  bool _isProcessing = false;

  Future<void> _toggle(bool enabled) async {
    if (_isProcessing) return;
    if (!Platform.isMacOS) {
      AppToast.show(context, context.l10n.t('receiverMacOnly'), isError: true);
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final notifier = ref.read(airplaySessionProvider.notifier);
      if (enabled) {
        await notifier.startServer(
          name: ref.read(appSettingsProvider).airplayServerName,
        );
      } else {
        await notifier.stopServer();
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          context.l10n.t('airplayFailed').replaceAll('{error}', '$error'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openActiveWindows(AirPlaySessionData session) async {
    final merged = mergeAirPlayDevicesIntoList(
      ref.read(deviceRegistryProvider),
      session,
    );
    for (final activeSession in session.mirroringSessions) {
      final matchedId = merged.sessionByDeviceId.entries
          .where((entry) => entry.value.id == activeSession.id)
          .map((entry) => entry.key)
          .firstOrNull;
      final preferred = matchedId == null
          ? null
          : merged.devices
                .where((device) => device.id == matchedId)
                .firstOrNull;
      await openAirPlayMirrorWindow(
        activeSession,
        deviceId: preferred?.id,
        deviceName: preferred?.displayName,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(airplaySessionProvider);
    final settings = ref.watch(appSettingsProvider);
    final isMirroring = session?.hasAnyMirroring ?? false;
    final isVideoPlaying = session?.isVideoPlaying ?? false;
    final isRunning =
        session != null &&
        (session.hasAnyBroadcasting || session.hasAnyMirroring);
    final activeCount = session?.mirroringSessions.length ?? 0;

    final activeLabels = [
      if (isMirroring) context.l10n.t('receiverAirplayMirroring')
          .replaceAll('{count}', '$activeCount'),
      if (isVideoPlaying) context.l10n.t('airplayVideoTitle'),
    ];
    final statusLabel = activeLabels.isNotEmpty
        ? activeLabels.join(' · ')
        : isRunning
        ? context.l10n.t('receiverWaiting')
        : context.l10n.t('receiverStopped');
    final statusDetail = isMirroring || isVideoPlaying
        ? context.l10n.t('receiverAirplayActiveDesc')
        : isRunning
        ? context.l10n
              .t('receiverAirplayReadyDesc')
              .replaceAll('{name}', settings.airplayServerName)
        : context.l10n.t('receiverAirplayStoppedDesc');
    final statusColor = isMirroring || isVideoPlaying
        ? theme.appColors.success
        : isRunning
        ? theme.colorScheme.primary
        : theme.appColors.faintForeground;

    return ReceiverServiceCard(
      icon: Icons.airplay_rounded,
      title: context.l10n.t('airplayServer'),
      description: context.l10n.t('receiverAirplayDesc'),
      statusLabel: statusLabel,
      statusDetail: statusDetail,
      statusColor: statusColor,
      value: isRunning,
      isBusy: _isProcessing,
      switchKey: const Key('airplayReceiverSwitch'),
      onChanged: _toggle,
      action: isMirroring || isVideoPlaying
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isMirroring) OutlinedButton.icon(
                  onPressed: () => _openActiveWindows(session!),
                  icon: const Icon(Icons.phone_iphone_rounded, size: 17),
                  label: Text(context.l10n.t('airplayOpenMirrorWindow')),
                ),
                if (isVideoPlaying) OutlinedButton.icon(
                  onPressed: () => ref.read(airplaySessionProvider.notifier).showVideoWindow(),
                  icon: const Icon(Icons.movie_outlined, size: 17),
                  label: Text(context.l10n.t('airplayOpenVideoWindow')),
                ),
              ],
            )
          : null,
      content: _ReceiverNameField(
        label: context.l10n.t('receiverName'),
        field: ReceiverNameSettingField(
          value: settings.airplayServerName,
          defaultName: AppSettings.defaultAirplayServerName,
          resetTooltip: context.l10n.t('iosAirplayNameReset'),
          onChanged: (value) => ref
              .read(appSettingsProvider.notifier)
              .setAirplayServerName(value),
          onApplied: restartAirplayBroadcastIfIdle,
        ),
      ),
    );
  }
}

/// DLNA 服务状态、视频会话状态与接收端名称入口。
class DlnaReceiverCard extends ConsumerStatefulWidget {
  const DlnaReceiverCard({super.key, this.service});

  /// 默认使用全局接收服务；测试可注入不启动网络的服务。
  final DlnaRendererService? service;

  @override
  ConsumerState<DlnaReceiverCard> createState() => _DlnaReceiverCardState();
}

class _DlnaReceiverCardState extends ConsumerState<DlnaReceiverCard> {
  late final _service = widget.service ?? DlnaRendererService.instance;
  String? _loadingText;
  String? _pinLabel;
  String? _unpinLabel;

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Platform.isMacOS) return;
    final loadingText = context.l10n.t('dlnaLoading');
    if (_loadingText != loadingText) {
      _loadingText = loadingText;
      unawaited(_service.setLoadingText(loadingText).catchError((_) {}));
    }
    final pinLabel = context.l10n.t('pinAlwaysOnTop');
    final unpinLabel = context.l10n.t('unpinAlwaysOnTop');
    if (_pinLabel != pinLabel || _unpinLabel != unpinLabel) {
      _pinLabel = pinLabel;
      _unpinLabel = unpinLabel;
      unawaited(_service.setPinLabels(pinLabel, unpinLabel).catchError((_) {}));
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle(bool enabled) async {
    if (_service.isBusy) return;
    if (!Platform.isMacOS) {
      AppToast.show(context, context.l10n.t('receiverMacOnly'), isError: true);
      return;
    }

    try {
      if (enabled) {
        await _service.setServerName(
          ref.read(appSettingsProvider).dlnaServerName,
        );
        await _service.start();
      } else {
        await _service.stop();
      }
      if (mounted) {
        AppToast.show(
          context,
          context.l10n
              .t(_service.isRunning ? 'dlnaStarted' : 'dlnaStopped')
              .replaceAll('{name}', _service.serverName),
        );
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          context.l10n.t('dlnaFailed').replaceAll('{error}', '$error'),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider);
    final hasError = _service.error != null && !_service.isRunning;
    final playbackFailed = _service.isRunning && _service.playbackError != null;
    final statusLabel = playbackFailed
        ? context.l10n.t('receiverDlnaPlaybackFailed')
        : hasError
        ? context.l10n.t('receiverFailed')
        : _service.hasActiveMedia
        ? context.l10n.t('receiverDlnaPlaying')
        : _service.isRunning
        ? context.l10n.t('receiverWaiting')
        : context.l10n.t('receiverStopped');
    final statusDetail = playbackFailed
        ? context.l10n.t('receiverDlnaPlaybackFailedDesc')
        : hasError
        ? context.l10n.t('receiverDlnaStartFailedDesc')
        : _service.hasActiveMedia
        ? context.l10n.t('receiverDlnaPlayingDesc')
        : _service.isRunning
        ? context.l10n
              .t('receiverDlnaReadyDesc')
              .replaceAll('{name}', settings.dlnaServerName)
        : context.l10n.t('receiverDlnaStoppedDesc');
    final statusColor = hasError || playbackFailed
        ? theme.colorScheme.error
        : _service.hasActiveMedia
        ? theme.appColors.success
        : _service.isRunning
        ? theme.colorScheme.primary
        : theme.appColors.faintForeground;

    return ReceiverServiceCard(
      icon: Icons.cast_connected_rounded,
      title: context.l10n.t('receiverDlnaTitle'),
      description: context.l10n.t('receiverDlnaDesc'),
      statusLabel: statusLabel,
      statusDetail: statusDetail,
      statusColor: statusColor,
      value: _service.isRunning,
      isBusy: _service.isBusy,
      switchKey: const Key('dlnaReceiverSwitch'),
      onChanged: _toggle,
      content: _ReceiverNameField(
        label: context.l10n.t('receiverName'),
        field: ReceiverNameSettingField(
          value: settings.dlnaServerName,
          defaultName: AppSettings.defaultDlnaServerName,
          resetTooltip: context.l10n.t('androidDlnaNameReset'),
          onChanged: (value) =>
              ref.read(appSettingsProvider.notifier).setDlnaServerName(value),
        ),
      ),
    );
  }
}

class _ReceiverNameField extends StatelessWidget {
  const _ReceiverNameField({required this.label, required this.field});

  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        field,
      ],
    );
  }
}
