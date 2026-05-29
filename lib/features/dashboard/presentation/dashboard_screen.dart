import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lpinyin/lpinyin.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/adb/adb_result.dart';
import '../../../core/apps/adb_package.dart';
import '../../../core/device_info/device_overview.dart';
import '../../../core/emulator/android_emulator.dart';
import '../../../core/files/remote_file.dart';
import '../../../core/logcat/logcat_controller.dart';
import '../../../core/logcat/logcat_entry.dart';
import '../../../core/logcat/logcat_state.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/scrcpy_launch_options.dart';
import '../../../core/scrcpy/scrcpy_session.dart';
import 'terminal_tab.dart';
import 'processes_tab.dart';
import 'webpages_tab.dart';
import 'layout_tab.dart';

part 'dashboard_shell.dart';
part 'dashboard_dialogs.dart';
part 'dashboard_emulators.dart';
part 'dashboard_workspace.dart';
part 'dashboard_device_header.dart';
part 'dashboard_overview.dart';
part 'dashboard_control.dart';
part 'dashboard_apps_tab.dart';
part 'dashboard_apps_table_widths.dart';
part 'dashboard_apps_table.dart';
part 'dashboard_apps_actions.dart';
part 'dashboard_files_tab.dart';
part 'dashboard_file_items.dart';
part 'dashboard_logcat.dart';
part 'dashboard_common.dart';
part 'dashboard_app_details.dart';
part 'dashboard_pairing.dart';
part 'dashboard_devices_panel.dart';
part 'dashboard_devices_view.dart';
part 'dashboard_devices_rows.dart';
part 'dashboard_devices_actions.dart';
part 'dashboard_screenshot_tab.dart';

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

/// 桌面主面板，整合设备发现和工具区域。
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDevice = ref.watch(selectedDeviceProvider);
    final sessions = ref.watch(scrcpySessionsProvider);
    final registeredDevices = ref.watch(deviceRegistryProvider);

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
        final syncedDevice = effectiveSelectedDevice!;
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

    final workspace = _WorkspacePanel(
      selectedDevice: effectiveSelectedDevice,
      sessions: sessions,
    );

    return Scaffold(
      body: _WechatStyleShell(
        title: appBarTitle,
        selectedDevice: effectiveSelectedDevice,
        child: selectedDevice == null
            ? const _DashboardHomeContent()
            : workspace,
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
