import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'package:path_provider/path_provider.dart';

import '../app/l10n/app_localizations.dart';
import '../app/router/dashboard_route.dart';
import '../app/theme/app_icon.dart';
import '../app/theme/app_navigation_icons.dart';
import '../app/theme/app_theme.dart';
import '../app/widget/dashboard_tab_layout.dart';
import '../app/widget/dashboard_history_text_field.dart';
import '../app/widget/app_detail_layout.dart';

import '../app/widget/app_toast.dart';
import '../app/settings/app_settings.dart';
import '../app/settings/app_settings_controller.dart';
import '../app/shortcuts/window_shortcut.dart';
import '../app/window/multi_window_compat.dart';
import '../app/window/console/console_window_launcher.dart';
import 'console/controller/console_dock_controller.dart';
import 'console/widgets/console_dock.dart';
import 'overview/widget/system_versions_page.dart';
import '../app/window/model/desktop_chrome_policy.dart';
import '../app/window/widget/desktop_workspace_surface.dart';
import '../app/window/mirror/mirror_aspect_resolver.dart';
import '../app/window/mirror/app_mirror_launch_coordinator.dart';
import '../core/scrcpy/fusion_mode_preference.dart';
import 'apps/widgets/fusion_mode_setting_row.dart';
import '../app/window/window_close_shortcut.dart';
import '../core/adb/discovered_device.dart';
import '../core/notifications/notification_click_target.dart';
import '../core/adb/adb_result.dart';
import '../core/apps/adb_package.dart';
import '../core/apps/adb_package_detail.dart';
import '../core/apps/app_management_service.dart';
import '../core/apps/harmony_app_detail.dart';
import 'apps/widgets/app_permissions_panel.dart';
import 'devices/widgets/adb_wireless_controls.dart';
import 'devices/widgets/device_connection_indicators.dart';
import 'devices/widgets/device_status_avatar.dart';
import 'devices/widgets/device_info_edit_dialog.dart';
import 'apps/widgets/package_refresh_dialog.dart';
import 'apps/widgets/apps_view_mode_button.dart';
import '../core/apps/package_refresh_progress.dart';
import '../core/cache/cache_cleanup_service.dart';
import '../core/device_info/device_overview.dart';
import '../core/device_info/device_battery_info.dart';
import '../core/device_info/android_version_helper.dart';
import '../core/device_info/screen_density_helper.dart';
import '../core/emulator/android_emulator.dart';
import '../core/emulator/emulator_process.dart';
import '../core/emulator/emulator_connection.dart';
import '../core/files/remote_file.dart';
import '../core/logcat/logcat_controller.dart';
import '../core/logcat/logcat_entry.dart';
import '../core/logcat/logcat_state.dart';
import '../core/providers/app_providers.dart';
import '../core/providers/network_providers.dart';
import '../core/providers/transfer_provider.dart';
import 'widgets/drag_drop_target_overlay.dart';
import '../core/adb/adb_environment_service.dart';
import '../core/scrcpy/scrcpy_session.dart';
import '../core/scrcpy/embedded_scrcpy_service.dart';
import '../core/scrcpy/screen_record_provider.dart';
import '../core/ios/ios_mirror_service.dart';
import '../core/ios/ios_overview_details.dart';
import '../core/device_actions/device_action_service.dart';
import '../core/device_actions/wifi_credentials.dart';
import 'control/device_settings_popup.dart';
import 'control/deeplink_feedback.dart';
import 'control/widgets/audio_forward_button.dart';
import 'control/widgets/camera_preview_dialog.dart';
import '../app/window/mirror/mirror_screen_recording_action.dart';
import 'terminal/terminal_tab.dart';
import 'terminal/harmony_terminal_tab.dart';
import 'processes/processes_tab.dart';
import 'processes/harmony_processes_tab.dart';
import 'webpages/webpages_tab.dart';
import 'webpages/harmony_webpages_tab.dart';
import 'screenshot/dashboard_screenshot_tab.dart';
import 'control/harmony_control_tab.dart';
import 'screenshot/harmony_screenshot_tab.dart';
import 'performance/performance_tab.dart';
import 'network/network_tab.dart';
import 'mcp/presentation/mcp_dashboard_tab.dart';
import 'mcp/controller/mcp_server_controller.dart';
import 'widgets/dashboard_snack.dart';
import 'widgets/remote_controller_dialog.dart';
import 'devices/widgets/tcpip_connection_dialog.dart';
import 'devices/widgets/device_share_dialog.dart';
import 'devices/widgets/device_share_controls.dart';
import '../core/device_share/device_share_provider.dart';
import 'devices/widgets/device_list_filters.dart';
import 'overview/widget/mirror_quality_presets.dart';
import 'overview/widget/keyboard_shortcut_settings.dart';
import 'overview/settings/settings_workspace.dart';
import 'overview/settings/settings_item.dart';
import '../app/shortcuts/mirror_shortcut.dart';
import 'devices/model/device_list_presentation.dart';
import 'devices/model/device_context_action.dart';
import 'devices/widgets/host_network_footer.dart';
import 'devices/widgets/device_subnet_warning.dart';
import 'devices/widgets/harmony_wireless_connection_view.dart';
import 'widgets/dashboard_table_header.dart';
import 'widgets/dashboard_header_bar.dart';
import 'devices/widgets/emulator_platform_tabs.dart';
import 'devices/widgets/ios_simulators_view.dart';
import 'devices/widgets/deveco_emulators_view.dart';
import '../core/search/dashboard_search_history_controller.dart';
import 'apps/controller/app_favorites_controller.dart';
import 'apps/controller/usage_report_controller.dart';
import 'apps/controller/usage_report_view_controller.dart';
import '../core/usage/usage_snapshot.dart';
import 'apps/widgets/location_history_view.dart';
import 'apps/widgets/apps_alphabet_sidebar.dart';
import 'airplay/airplay_mirror_target.dart';
import 'airplay/airplay_window_routing_provider.dart';
import 'receivers/receiver_dashboard_tab.dart';
import 'harmony_share/harmony_share_dashboard_tab.dart';
import 'harmony_share/controller/harmony_share_offer_presenter.dart';
import 'harmony_share/controller/harmony_share_providers.dart';
import '../core/nearby_share/harmony_share_notifications.dart';
import '../core/nearby_share/harmony_share_service.dart';
import 'devices/widgets/device_airplay_row_widgets.dart';
import '../core/airplay/airplay_server_service.dart';
import '../core/airplay/airplay_server_state.dart';
import '../core/dlna/dlna_renderer_service.dart';
import 'files/controller/file_favorite_folders_controller.dart';
import 'files/controller/file_preview_controller.dart';
import 'files/controller/file_selection_controller.dart';
import 'files/widgets/file_history_filter_field.dart';
import 'ios/ios_apps_tab.dart';
import 'ios/ios_automation_tab.dart';
import 'ios/ios_files_tab.dart';
import 'ios/ios_processes_tab.dart';
import 'ios/ios_syslog_tab.dart';
import 'ios/ios_web_inspector_tab.dart';
import 'webview/in_app_webview_widget.dart';
import 'overview/widget/android_version_distribution_launcher.dart';
import 'overview/model/platform_distribution_type.dart';
import 'overview/widget/tool_directory_menu_button.dart';
import 'overview/widget/service_restart_menu_button.dart';
import 'overview/widget/receiver_name_setting_field.dart';
import 'messages/presentation/messages_tab.dart';
import 'messages/presentation/controller/messages_controller.dart';
import '../core/notifications/notification_providers.dart';
import '../core/notifications/mac_notification_bridge.dart';
import '../core/dal/device_driver.dart';
import '../core/dal/rust_dal_bridge.dart';
import 'developer/widget/settings_developer_entry.dart';
import 'feedback/widget/settings_feedback_entry.dart';

part 'overview/dashboard_shell.dart';
part 'overview/dashboard_content.dart';
part 'overview/dashboard_quit_shortcut.dart';
part 'overview/dashboard_rail.dart';
part 'overview/dashboard_rail_buttons.dart';
part 'overview/dashboard_rail_footer.dart';
part 'overview/dashboard_rail_identity.dart';
part 'widgets/dashboard_update_dialog.dart';
part 'devices/dashboard_emulators.dart';
part 'devices/dashboard_emulator_layout.dart';
part 'devices/dashboard_emulator_error.dart';
part 'devices/dashboard_emulator_item.dart';
part 'devices/dashboard_emulators_header.dart';
part 'devices/dashboard_emulators_table.dart';
part 'devices/dashboard_emulator_details.dart';
part 'overview/dashboard_workspace.dart';
part 'overview/dashboard_route_sync.dart';
part 'devices/device_mirror_window_launcher.dart';
part 'overview/dashboard_overview.dart';
part 'overview/dashboard_overview_widgets.dart';
part 'overview/dashboard_overview_battery_chip.dart';
part 'overview/dashboard_overview_details.dart';
part 'overview/dashboard_ios_overview_details.dart';
part 'overview/dashboard_overview_components.dart';
part 'overview/dashboard_overview_capacity_card.dart';
part 'control/dashboard_control.dart';
part 'control/widget/device_capture_actions.dart';
part 'control/dashboard_deeplink.dart';
part 'control/dashboard_power.dart';
part 'control/dashboard_display_control.dart';
part 'control/wifi_passwords_dialog.dart';
part 'control/dashboard_certificate.dart';
part 'control/certificate_import_dialog.dart';
part 'apps/dashboard_apps_tab.dart';
part 'apps/dashboard_apps_view.dart';
part 'apps/dashboard_apps_context_menu.dart';
part 'apps/dashboard_apps_table_widths.dart';
part 'apps/dashboard_apps_table.dart';
part 'apps/dashboard_apps_table_row.dart';
part 'apps/dashboard_apps_grid.dart';
part 'apps/widgets/package_icon.dart';
part 'apps/dashboard_apps_actions.dart';
part 'apps/dashboard_apps_batch_actions.dart';
part 'apps/dashboard_apps_batch_progress_state.dart';
part 'apps/dashboard_harmony_app_context_menu.dart';
part 'apps/widgets/usage_report_dialog.dart';
part 'files/dashboard_files_tab.dart';
part 'files/harmony_files_tab.dart';
part 'files/dashboard_file_quick_access.dart';
part 'files/dashboard_file_type_icon.dart';
part 'files/dashboard_file_interactions.dart';
part 'files/dashboard_file_breadcrumbs.dart';
part 'files/dashboard_file_preview.dart';
part 'files/dashboard_file_path_field.dart';
part 'files/dashboard_files_table_header.dart';
part 'files/dashboard_files_layout.dart';
part 'files/dashboard_file_items.dart';
part 'logcat/dashboard_logcat.dart';
part 'logcat/harmony_logcat_tab.dart';
part 'logcat/dashboard_logcat_toolbar.dart';
part 'logcat/dashboard_logcat_list.dart';
part 'logcat/dashboard_logcat_table.dart';
part 'logcat/dashboard_logcat_widgets.dart';
part 'widgets/dashboard_common.dart';
part 'apps/dashboard_app_details_tabs.dart';
part 'apps/dashboard_app_details_tabs_2.dart';
part 'apps/dashboard_app_native_library_rules.dart';
part 'apps/dashboard_app_signature_tab.dart';
part 'apps/dashboard_app_permissions.dart';
part 'apps/dashboard_app_functions_view.dart';
part 'apps/harmony_apps_tab.dart';
part 'apps/harmony_app_analysis_view.dart';
part 'devices/device_wireless_connection_dialog.dart';
part 'devices/dashboard_devices_panel.dart';
part 'devices/dashboard_devices_context_menu.dart';
part 'devices/dashboard_devices_view.dart';
part 'devices/dashboard_devices_rows.dart';
part 'devices/dashboard_devices_actions.dart';
part 'devices/dashboard_batch_actions.dart';
part 'screenshot/dashboard_screenshot_recording.dart';
part 'overview/dashboard_settings_tab.dart';
part 'overview/dashboard_settings_catalog.dart';
part 'overview/dashboard_settings_media.dart';
part 'overview/dashboard_cache_settings.dart';
part 'overview/dashboard_settings_widgets.dart';
part 'overview/dashboard_notification_settings.dart';
part 'overview/dashboard_autostart_settings.dart';

class _EmulatorListExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() {
    state = !state;
  }
}

final _emulatorListExpandedProvider =
    NotifierProvider<_EmulatorListExpandedNotifier, bool>(
      _EmulatorListExpandedNotifier.new,
    );

class _LastActiveDeviceNotifier extends Notifier<DiscoveredDevice?> {
  @override
  DiscoveredDevice? build() => null;

  @override
  set state(DiscoveredDevice? value) => super.state = value;
}

final lastActiveDeviceProvider =
    NotifierProvider<_LastActiveDeviceNotifier, DiscoveredDevice?>(
      _LastActiveDeviceNotifier.new,
    );

/// 桌面主面板，整合设备发现和工具区域。
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key, this.route});

  /// 由 GoRouter 提供；测试或独立嵌入时可为空并沿用 Provider 状态。
  final DashboardRouteState? route;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WindowListener {
  static const _windowChannel = MethodChannel('any_deck/window');
  static const _quitShortcutInterval = Duration(seconds: 2);

  DateTime? _lastQuitShortcutAt;
  bool _hasVisitedWanAndroid = false;
  bool _isAirplayReceiverRunning = false;
  bool _routeSyncScheduled = false;
  String? _resolvedRouteDeviceId;
  StreamSubscription<Map<String, dynamic>>? _notificationClickSub;
  late final HarmonyShareOfferPresenter _shareOfferPresenter;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _windowChannel.setMethodCallHandler(_handleWindowMethodCall);
    _notificationClickSub = ref
        .read(macNotificationBridgeProvider)
        .clickStream
        .listen(_handleNotificationClick);
    _shareOfferPresenter = HarmonyShareOfferPresenter(
      incoming: ref.read(harmonyShareNotificationsProvider).incoming,
      context: () => context,
    );
    unawaited(HarmonyShareService.instance.start());
    _scheduleDashboardRouteSync();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialClicks =
          await ref.read(macNotificationBridgeProvider).ready();
      for (final click in initialClicks) {
        _handleNotificationClick(click);
      }
      if (mounted) {
        ref.read(adbEnvironmentProvider.notifier).checkAndPromptIfNeeded(context);
      }
    });
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) {
      _scheduleDashboardRouteSync();
    }
  }

  @override
  void dispose() {
    _shareOfferPresenter.dispose();
    unawaited(HarmonyShareService.instance.stop());
    _notificationClickSub?.cancel();
    _windowChannel.setMethodCallHandler(null);
    windowManager.removeListener(this);
    super.dispose();
  }

  int _notificationClickRevision = 0;

  Future<void> _handleNotificationClick(Map<String, dynamic> payload) async {
    if (!mounted) return;
    final revision = ++_notificationClickRevision;
    if (ref.read(harmonyShareNotificationsProvider).incoming.handleClick(payload)) {
      return;
    }
    if (routeHarmonyShareNotification(payload, () {
      if (mounted) context.goNamed(AppRouteNames.harmonyShare);
    })) {
      return;
    }
    final type = payload['type'] as String?;
    final deviceId = payload['deviceId'] as String?;
    final deviceSerial = payload['deviceSerial'] as String?;
    final rawTargetTab = payload['targetTab'];
    final targetTab = rawTargetTab is num
        ? rawTargetTab.toInt()
        : rawTargetTab == 'messages' || type == 'phone_message'
        ? 15
        : 0;
    final messageId = (payload['messageId'] as num?)?.toInt();
    final notificationKey = payload['notificationKey'] as String?;

    if (deviceId != null && deviceId.isNotEmpty) {
      final registry = ref.read(deviceRegistryProvider);
      final installationId = payload['installationId'] as String?;
      final userId = (payload['androidUserId'] as num?)?.toInt();
      final database = await ref.read(notificationDatabaseProvider.future);
      if (!mounted || revision != _notificationClickRevision) return;
      final matched = await resolveNotificationClickDevice(
        devices: registry,
        database: database,
        deviceId: deviceId,
        deviceSerial: deviceSerial,
        installationId: installationId,
        userId: userId,
      );
      if (!mounted || revision != _notificationClickRevision) return;
      if (matched == null) {
        context.goNamed(AppRouteNames.devices);
        ref.read(messageClickTargetProvider.notifier).state = null;
        ref.read(targetMessageIdProvider.notifier).state = null;
        ref.read(highlightedNotificationKeyProvider.notifier).state = null;
        if (mounted) {
          _showSnack(
            context,
            context.l10n.t('deviceDeletedOrNotFound'),
            isError: true,
          );
        }
        return;
      }
      ref
          .read(messageClickTargetProvider.notifier)
          .state = installationId != null && userId != null
          ? (
              deviceId: matched.id,
              serial: matched.serial,
              installationId: installationId,
              userId: userId,
            )
          : null;
      ref.read(messagesSearchQueryProvider.notifier).state = '';
      ref.read(messagesPackageFilterProvider.notifier).state = null;
      ref.read(targetMessageIdProvider.notifier).state = messageId;
      ref.read(highlightedNotificationKeyProvider.notifier).state =
          notificationKey?.isNotEmpty == true ? notificationKey : null;
      _goToDeviceTool(matched.id, targetTab);
    }
  }

  @override
  void onWindowFocus() {
    ref.read(devicePollingControllerProvider).trigger();
  }

  Future<void> _handleWindowMethodCall(MethodCall call) async {
    if (call.method == 'openMirrorWindow') {
      final selectedDevice = ref.read(selectedDeviceProvider);
      if (selectedDevice != null && selectedDevice.isOnline) {
        openStandaloneMirrorWindow(context, ref, selectedDevice);
      } else {
        if (mounted) {
          _showSnack(
            context,
            context.l10n.t('selectDeviceToMirror'),
            isError: true,
          );
        }
      }
    } else if (call.method == 'openConsoleWindow') {
      openConsoleWindow(context);
    } else if (call.method == 'openPreferences') {
      context.goNamed(AppRouteNames.settings);
    }
  }

  Future<void> _exitApp() async {
    await ref.read(deviceShareServiceProvider).dispose();
    // 退出应用，先解除关闭拦截，然后销毁窗口并退出进程
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onWindowClose() async {
    // 点击关闭按钮默认最小化（隐藏窗口到系统托盘）
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(deviceConnectionNotificationServiceProvider);
    ref.watch(notificationForwardingServiceProvider);

    ref.watch(airplayWindowRoutingProvider);
    // 接收服务指示灯与独立开窗协调器分离。
    ref.listen<AirPlaySessionData?>(airplaySessionProvider, (previous, next) {
      final isRunning = next != null &&
          (next.hasAnyBroadcasting || next.hasAnyMirroring);
      if (_isAirplayReceiverRunning != isRunning) {
        setState(() => _isAirplayReceiverRunning = isRunning);
      }
    });

    return _buildDashboardContent(context);
  }

  bool _hasDeviceSnapshotChanged(DiscoveredDevice left, DiscoveredDevice? right) {
    return right == null ||
        left.id != right.id ||
        left.status != right.status ||
        left.model != right.model ||
        left.product != right.product ||
        left.transportId != right.transportId;
  }
}
