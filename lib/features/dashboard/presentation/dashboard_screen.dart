import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:window_manager/window_manager.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/adb/adb_result.dart';
import '../../../core/apps/adb_package.dart';
import '../../../core/apps/adb_app_permission.dart';
import '../../../core/device_info/device_overview.dart';
import '../../../core/device_info/brand_logo_helper.dart';
import '../../../core/device_info/android_version_helper.dart';
import '../../../core/device_info/screen_density_helper.dart';
import '../../../core/emulator/android_emulator.dart';
import '../../../core/files/remote_file.dart';
import '../../../core/logcat/logcat_controller.dart';
import '../../../core/logcat/logcat_entry.dart';
import '../../../core/logcat/logcat_state.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/network_providers.dart';
import '../../../core/scrcpy/scrcpy_launch_options.dart';
import '../../../core/scrcpy/scrcpy_session.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/device_actions/device_action_service.dart';
import 'control/embedded_scrcpy_viewer.dart';
import 'terminal/terminal_tab.dart';
import 'processes/processes_tab.dart';
import 'webpages/webpages_tab.dart';
import 'layout/layout_tab.dart';
import 'performance/performance_tab.dart';
import 'network/network_tab.dart';


part 'overview/dashboard_shell.dart';
part 'widgets/dashboard_dialogs.dart';
part 'widgets/remote_controller_dialog.dart';
part 'devices/dashboard_emulators.dart';
part 'devices/dashboard_emulator_details.dart';
part 'overview/dashboard_workspace.dart';
part 'devices/dashboard_device_header.dart';
part 'overview/dashboard_overview.dart';
part 'control/dashboard_control.dart';
part 'control/dashboard_power.dart';
part 'control/dashboard_display_control.dart';
part 'apps/dashboard_apps_tab.dart';
part 'apps/dashboard_apps_table_widths.dart';
part 'apps/dashboard_apps_table.dart';
part 'apps/dashboard_apps_grid.dart';
part 'apps/dashboard_apps_actions.dart';
part 'files/dashboard_files_tab.dart';
part 'files/dashboard_file_items.dart';
part 'logcat/dashboard_logcat.dart';
part 'widgets/dashboard_common.dart';
part 'apps/dashboard_app_details.dart';
part 'apps/dashboard_app_permissions.dart';
part 'devices/dashboard_pairing.dart';
part 'devices/dashboard_devices_panel.dart';
part 'devices/dashboard_devices_view.dart';
part 'devices/dashboard_devices_rows.dart';
part 'devices/dashboard_devices_actions.dart';
part 'devices/dashboard_batch_actions.dart';
part 'screenshot/dashboard_screenshot_tab.dart';
part 'screenshot/dashboard_screenshot_recording.dart';

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

class _DashboardScreenState extends ConsumerState<DashboardScreen> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ExitConfirmDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDevice = ref.watch(selectedDeviceProvider);
    final sessions = ref.watch(scrcpySessionsProvider);
    final registeredDevices = ref.watch(deviceRegistryProvider);
    final lastActiveDevice = ref.watch(lastActiveDeviceProvider);

    // Auto-select first online device if none selected and not manually cleared
    final userCleared = ref.watch(userClearedDeviceSelectionProvider);
    if (selectedDevice == null && !userCleared) {
      final onlineDevices = registeredDevices.where((d) => d.isOnline).toList();
      if (onlineDevices.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ref.read(selectedDeviceProvider) == null &&
              !ref.read(userClearedDeviceSelectionProvider)) {
            ref
                .read(selectedDeviceProvider.notifier)
                .select(onlineDevices.first.toAdbDevice);
          }
        });
      }
    }

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
        if (ref.read(lastActiveDeviceProvider) != effectiveSelectedDevice) {
          ref.read(lastActiveDeviceProvider.notifier).state = effectiveSelectedDevice;
        }
      });
    }

    final workspace = _WorkspacePanel(
      selectedDevice: effectiveSelectedDevice ?? lastActiveDevice,
      sessions: sessions,
    );

    return Scaffold(
      body: _WechatStyleShell(
        title: appBarTitle,
        selectedDevice: effectiveSelectedDevice,
        child: IndexedStack(
          index: selectedDevice == null ? 0 : 1,
          children: [
            const _DashboardHomeContent(),
            workspace,
          ],
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
