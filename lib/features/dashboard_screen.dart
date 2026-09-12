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
import 'package:lpinyin/lpinyin.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'package:path_provider/path_provider.dart';

import '../app/l10n/app_localizations.dart';
import '../app/theme/app_icon.dart';
import '../app/widget/dashboard_tab_layout.dart';

import '../app/settings/app_settings.dart';
import '../app/settings/app_settings_controller.dart';
import '../app/window/multi_window_compat.dart';
import '../app/window/window_close_shortcut.dart';
import '../core/adb/adb_device.dart';
import '../core/adb/adb_result.dart';
import '../core/apps/adb_package.dart';
import '../core/apps/adb_package_detail.dart';
import 'apps/widgets/app_permissions_panel.dart';
import 'apps/widgets/package_refresh_dialog.dart';
import '../core/apps/package_refresh_progress.dart';
import '../core/cache/cache_cleanup_service.dart';
import '../core/device_info/device_overview.dart';
import '../core/device_info/brand_logo_helper.dart';
import '../core/device_info/screen_density_helper.dart';
import '../core/emulator/android_emulator.dart';
import '../core/files/remote_file.dart';
import '../core/logcat/logcat_controller.dart';
import '../core/logcat/logcat_entry.dart';
import '../core/logcat/logcat_state.dart';
import '../core/providers/app_providers.dart';
import '../core/providers/network_providers.dart';
import '../core/providers/transfer_provider.dart';
import '../core/utils/network_util.dart';
import 'widgets/drag_drop_target_overlay.dart';
import 'widgets/liquid_glass_background.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../core/scrcpy/scrcpy_session.dart';
import '../core/scrcpy/embedded_scrcpy_service.dart';
import '../core/ios/ios_mirror_service.dart';
import '../core/device_actions/device_action_service.dart';
import '../core/device_actions/wifi_credentials.dart';
import 'control/device_settings_popup.dart';
import 'terminal/terminal_tab.dart';
import 'processes/processes_tab.dart';
import 'webpages/webpages_tab.dart';
import 'screenshot/dashboard_screenshot_tab.dart';
import 'performance/performance_tab.dart';
import 'network/network_tab.dart';
import 'mcp/presentation/mcp_dashboard_tab.dart';
import 'mcp/controller/mcp_server_controller.dart';
import 'widgets/dashboard_snack.dart';
import 'widgets/dashboard_table_header.dart';
import 'widgets/device_power_actions.dart';
import 'apps/controller/apps_search_history_controller.dart';
import 'apps/controller/usage_report_controller.dart';
import 'apps/controller/usage_report_view_controller.dart';
import '../core/usage/usage_snapshot.dart';
import 'apps/widgets/location_history_view.dart';
import 'files/controller/file_favorite_folders_controller.dart';
import 'files/controller/file_preview_controller.dart';
import 'files/controller/file_selection_controller.dart';
import 'ios/ios_apps_tab.dart';
import 'ios/ios_automation_tab.dart';
import 'ios/ios_files_tab.dart';
import 'ios/ios_processes_tab.dart';
import 'ios/ios_syslog_tab.dart';
import 'webview/in_app_webview_widget.dart';
import 'overview/widget/android_version_distribution_launcher.dart';

part 'overview/dashboard_shell.dart';
part 'overview/dashboard_rail.dart';
part 'overview/dashboard_rail_identity.dart';
part 'widgets/dashboard_dialogs.dart';
part 'widgets/dashboard_update_dialog.dart';
part 'widgets/remote_controller_dialog.dart';
part 'devices/dashboard_emulators.dart';
part 'devices/dashboard_emulators_header.dart';
part 'devices/dashboard_emulators_table.dart';
part 'devices/dashboard_emulator_details.dart';
part 'overview/dashboard_workspace.dart';
part 'devices/dashboard_device_header.dart';
part 'overview/dashboard_overview.dart';
part 'overview/dashboard_overview_widgets.dart';
part 'overview/dashboard_overview_components.dart';
part 'overview/dashboard_overview_capacity_card.dart';
part 'control/dashboard_control.dart';
part 'control/dashboard_deeplink.dart';
part 'control/dashboard_power.dart';
part 'control/dashboard_display_control.dart';
part 'control/wifi_passwords_dialog.dart';
part 'control/dashboard_certificate.dart';
part 'control/certificate_import_dialog.dart';
part 'apps/dashboard_apps_tab.dart';
part 'apps/dashboard_apps_table_widths.dart';
part 'apps/dashboard_apps_table.dart';
part 'apps/dashboard_apps_table_row.dart';
part 'apps/dashboard_apps_grid.dart';
part 'apps/dashboard_apps_actions.dart';
part 'apps/widgets/usage_report_dialog.dart';
part 'files/dashboard_files_tab.dart';
part 'files/dashboard_file_quick_access.dart';
part 'files/dashboard_file_type_icon.dart';
part 'files/dashboard_file_interactions.dart';
part 'files/dashboard_file_breadcrumbs.dart';
part 'files/dashboard_file_preview.dart';
part 'files/dashboard_file_path_field.dart';
part 'files/dashboard_files_table_header.dart';
part 'files/dashboard_file_items.dart';
part 'logcat/dashboard_logcat.dart';
part 'logcat/dashboard_logcat_toolbar.dart';
part 'logcat/dashboard_logcat_list.dart';
part 'logcat/dashboard_logcat_table.dart';
part 'logcat/dashboard_logcat_widgets.dart';
part 'widgets/dashboard_common.dart';
part 'apps/dashboard_app_details_tabs.dart';
part 'apps/dashboard_app_details_tabs_2.dart';
part 'apps/dashboard_app_signature_tab.dart';
part 'apps/dashboard_app_permissions.dart';
part 'apps/dashboard_app_functions_view.dart';
part 'devices/dashboard_pairing.dart';
part 'devices/dashboard_devices_panel.dart';
part 'devices/dashboard_devices_view.dart';
part 'devices/dashboard_devices_rows.dart';
part 'devices/dashboard_devices_actions.dart';
part 'devices/dashboard_batch_actions.dart';
part 'screenshot/dashboard_screenshot_recording.dart';
part 'overview/dashboard_settings_tab.dart';
part 'overview/dashboard_cache_settings.dart';
part 'overview/dashboard_settings_widgets.dart';

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

class _LastActiveDeviceNotifier extends Notifier<AdbDevice?> {
  @override
  AdbDevice? build() => null;

  @override
  set state(AdbDevice? value) => super.state = value;
}

final lastActiveDeviceProvider =
    NotifierProvider<_LastActiveDeviceNotifier, AdbDevice?>(
      _LastActiveDeviceNotifier.new,
    );

/// 桌面主面板，整合设备发现和工具区域。
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WindowListener {
  static const _windowChannel = MethodChannel('any_deck/window');
  static const _quitShortcutInterval = Duration(seconds: 2);

  DateTime? _lastQuitShortcutAt;
  bool _hasVisitedWanAndroid = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _windowChannel.setMethodCallHandler(_handleWindowMethodCall);
  }

  @override
  void dispose() {
    _windowChannel.setMethodCallHandler(null);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() {
    ref.read(adbHeartbeatControllerProvider).trigger();
  }

  Future<void> _handleWindowMethodCall(MethodCall call) async {
    if (call.method == 'openEmulatorManager') {
      EmulatorListPanel.openStandaloneWindow(context);
    } else if (call.method == 'openMirrorWindow') {
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
      _openConsoleWindow(context);
    } else if (call.method == 'openPreferences') {
      ref.read(selectedToolTabProvider.notifier).select(12);
    }
  }

  Future<void> _exitApp() async {
    // 退出应用，先解除关闭拦截，然后销毁窗口并退出进程
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  void _handleQuitShortcut() {
    final now = DateTime.now();
    final lastPressedAt = _lastQuitShortcutAt;
    if (lastPressedAt != null &&
        now.difference(lastPressedAt) <= _quitShortcutInterval) {
      _lastQuitShortcutAt = null;
      unawaited(_exitApp());
      return;
    }

    _lastQuitShortcutAt = now;
    DashboardSnack.show(context, context.l10n.t('pressCommandQAgainToQuit'));
  }

  @override
  void onWindowClose() async {
    // 点击关闭按钮默认最小化（隐藏窗口到系统托盘）
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDevice = ref.watch(selectedDeviceProvider);
    final sessions = ref.watch(scrcpySessionsProvider);
    final registeredDevices = ref.watch(deviceRegistryProvider);
    final lastActiveDevice = ref.watch(lastActiveDeviceProvider);

    var effectiveSelectedDevice = selectedDevice;
    String appBarTitle = context.l10n.t('appTitle');
    if (selectedDevice != null) {
      final matchedDevice = registeredDevices.firstWhere(
        (d) => d.id == selectedDevice.id,
        orElse: () => RegisteredDevice(
          id: selectedDevice.id,
          status: selectedDevice.status,
          model: selectedDevice.model,
          product: selectedDevice.product,
          transportId: selectedDevice.transportId,
          isOnline: selectedDevice.isOnline,
          serial: selectedDevice.id,
        ),
      );
      effectiveSelectedDevice = matchedDevice.toAdbDevice;
      appBarTitle = matchedDevice.displayName;

      if (_hasDeviceSnapshotChanged(selectedDevice, effectiveSelectedDevice)) {
        final syncedDevice = effectiveSelectedDevice;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final current = ref.read(selectedDeviceProvider);
          if (current != null &&
              current.id == syncedDevice.id &&
              _hasDeviceSnapshotChanged(current, syncedDevice)) {
            ref.read(selectedDeviceProvider.notifier).select(syncedDevice);
          }
        });
      }
    }

    if (effectiveSelectedDevice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final current = ref.read(lastActiveDeviceProvider);
        if (_hasDeviceSnapshotChanged(effectiveSelectedDevice!, current)) {
          ref.read(lastActiveDeviceProvider.notifier).state =
              effectiveSelectedDevice;
        }

        // iOS 仅开放已接入 go-ios 的工具页。
        if (effectiveSelectedDevice.isIos) {
          final selectedTool = ref.read(selectedToolTabProvider);
          const iosTabs = {0, 1, 2, 3, 4, 6, 9, 12, 13, 14};
          if (selectedTool != -1 && !iosTabs.contains(selectedTool)) {
            ref.read(selectedToolTabProvider.notifier).select(0);
          }
        } else if (effectiveSelectedDevice.isHarmony) {
          // 鸿蒙设备仅支持主页(0)、控制(1)、文件(3)、截图(9)、设置(12)、玩安卓(13)、AI MCP(14)
          final selectedTool = ref.read(selectedToolTabProvider);
          if (selectedTool != -1 &&
              selectedTool != 0 &&
              selectedTool != 1 &&
              selectedTool != 3 &&
              selectedTool != 9 &&
              selectedTool != 12 &&
              selectedTool != 13 &&
              selectedTool != 14) {
            ref.read(selectedToolTabProvider.notifier).select(0);
          }
        } else if (!effectiveSelectedDevice.isOnline) {
          // 当手机离线时，如果当前选择的不是主页(0)、控制(1)、应用(2)、设置(12)、玩安卓(13)或 AI MCP(14) Tab，则自动重定向回主页 Tab
          final selectedTool = ref.read(selectedToolTabProvider);
          if (selectedTool != -1 &&
              selectedTool != 0 &&
              selectedTool != 1 &&
              selectedTool != 2 &&
              selectedTool != 12 &&
              selectedTool != 13 &&
              selectedTool != 14) {
            ref.read(selectedToolTabProvider.notifier).select(0);
          }
        }
      });
    }

    final selectedTool = ref.watch(selectedToolTabProvider);
    final workspace = _WorkspacePanel(
      selectedDevice: effectiveSelectedDevice ?? lastActiveDevice,
      sessions: sessions,
    );

    final int stackIndex;
    if (selectedTool == 12) {
      stackIndex = 2;
    } else if (selectedTool == 13) {
      stackIndex = 3;
      _hasVisitedWanAndroid = true;
    } else if (selectedTool == 14) {
      stackIndex = 4;
    } else if (selectedTool == -1 || effectiveSelectedDevice == null) {
      stackIndex = 0;
    } else {
      stackIndex = 1;
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyQ, meta: true):
            _handleQuitShortcut,
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true):
            _handleQuitShortcut,
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () {
          ref.read(selectedToolTabProvider.notifier).select(12);
        },
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () {
          ref.read(selectedToolTabProvider.notifier).select(12);
        },
      },
      child: MainWindowCloseShortcut(
        child: Scaffold(
          body: _WechatStyleShell(
            title: appBarTitle,
            selectedDevice: effectiveSelectedDevice,
            child: IndexedStack(
              index: stackIndex,
              children: [
                const _DashboardHomeContent(),
                workspace,
                const _SettingsTab(),
                if (_hasVisitedWanAndroid)
                  const InAppWebViewWidget(
                    initialUrl: 'https://www.wanandroid.com/',
                    title: '玩Android',
                  )
                else
                  const SizedBox.shrink(),
                const McpDashboardTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _hasDeviceSnapshotChanged(AdbDevice left, AdbDevice? right) {
    return right == null ||
        left.id != right.id ||
        left.status != right.status ||
        left.model != right.model ||
        left.product != right.product ||
        left.transportId != right.transportId;
  }
}
