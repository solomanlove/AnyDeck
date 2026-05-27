import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/adb/adb_result.dart';
import '../../../core/apps/adb_package.dart';
import '../../../core/files/remote_file.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/scrcpy_launch_options.dart';
import '../../../core/scrcpy/scrcpy_session.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDevice = ref.watch(selectedDeviceProvider);
    final sessions = ref.watch(scrcpySessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AdbManage'),
        actions: [
          Tooltip(
            message: context.l10n.t('refreshDevices'),
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(devicesProvider),
            ),
          ),
          Tooltip(
            message: context.l10n.t('settings'),
            child: IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _SettingsDialog(),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          const _AppRail(),
          const VerticalDivider(width: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 980;
                final workspace = _WorkspacePanel(
                  selectedDevice: selectedDevice,
                  sessions: sessions,
                );

                if (compact) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [
                      _DeviceListPanel(),
                      SizedBox(height: 16),
                      _WorkspaceSlot(),
                    ],
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 360, child: _DeviceListPanel()),
                      const SizedBox(width: 16),
                      Expanded(child: workspace),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceSlot extends ConsumerWidget {
  const _WorkspaceSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _WorkspacePanel(
      selectedDevice: ref.watch(selectedDeviceProvider),
      sessions: ref.watch(scrcpySessionsProvider),
    );
  }
}

class _AppRail extends ConsumerWidget {
  const _AppRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = ref.watch(selectedToolTabProvider);
    final railIndex = switch (tabIndex) {
      2 => 1,
      3 => 2,
      _ => 0,
    };

    return NavigationRail(
      selectedIndex: railIndex,
      onDestinationSelected: (index) {
        final nextTab = switch (index) {
          1 => 2,
          2 => 3,
          _ => 0,
        };
        ref.read(selectedToolTabProvider.notifier).select(nextTab);
      },
      labelType: NavigationRailLabelType.all,
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.devices_other_outlined),
          selectedIcon: const Icon(Icons.devices_other),
          label: Text(context.l10n.t('devices')),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.folder_outlined),
          selectedIcon: const Icon(Icons.folder),
          label: Text(context.l10n.t('files')),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.article_outlined),
          selectedIcon: const Icon(Icons.article),
          label: Text(context.l10n.t('logcat')),
        ),
      ],
    );
  }
}

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    return AlertDialog(
      title: Text(context.l10n.t('settings')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<AppLanguage>(
              initialValue: settings.language,
              decoration: InputDecoration(
                labelText: context.l10n.t('language'),
              ),
              items: [
                DropdownMenuItem(
                  value: AppLanguage.zh,
                  child: Text(context.l10n.t('chinese')),
                ),
                DropdownMenuItem(
                  value: AppLanguage.en,
                  child: Text(context.l10n.t('english')),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.setLanguage(value);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ThemeMode>(
              initialValue: settings.themeMode,
              decoration: InputDecoration(labelText: context.l10n.t('theme')),
              items: [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(context.l10n.t('themeSystem')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(context.l10n.t('themeLight')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(context.l10n.t('themeDark')),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.setThemeMode(value);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('close')),
        ),
      ],
    );
  }
}

class _DeviceListPanel extends ConsumerWidget {
  const _DeviceListPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  context.l10n.t('devices'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Tooltip(
                  message: context.l10n.t('connectTcp'),
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.add_link),
                    onPressed: () => _showConnectDialog(context, ref),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            devices.when(
              loading: () => _PanelMessage(
                icon: Icons.sync,
                title: context.l10n.t('scanningDevices'),
              ),
              error: (error, stackTrace) => _PanelMessage(
                icon: Icons.error_outline,
                title: context.l10n.t('adbUnavailable'),
                subtitle: error.toString(),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return _PanelMessage(
                    icon: Icons.usb_off_outlined,
                    title: context.l10n.t('noDevices'),
                    subtitle: context.l10n.t('connectUsbOrTcp'),
                  );
                }

                return Column(
                  children: [
                    for (final device in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DeviceTile(device: device),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showConnectDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: '192.168.1.10:5555');
    final address = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.t('connectDevice')),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: context.l10n.t('ipAddress')),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.t('cancel')),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add_link),
              label: Text(context.l10n.t('connect')),
              onPressed: () => Navigator.of(context).pop(controller.text),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (address == null || address.trim().isEmpty || !context.mounted) {
      return;
    }

    await _runAdbAction(
      context,
      ref.read(deviceActionServiceProvider).connect(address.trim()),
    );
    ref.invalidate(devicesProvider);
  }
}

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDeviceProvider)?.id == device.id;

    return ListTile(
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(
        device.isOnline ? Icons.phone_android : Icons.phonelink_off,
        color: device.isOnline
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
      title: Text(device.displayName),
      subtitle: Text('${device.id} · ${device.status}'),
      trailing: device.transportId == null
          ? null
          : Text('#${device.transportId}'),
      onTap: () {
        ref.read(selectedDeviceProvider.notifier).select(device);
      },
    );
  }
}

class _WorkspacePanel extends ConsumerWidget {
  const _WorkspacePanel({required this.selectedDevice, required this.sessions});

  final AdbDevice? selectedDevice;
  final Map<String, ScrcpySession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = selectedDevice;

    if (device == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _PanelMessage(
            icon: Icons.ads_click,
            title: context.l10n.t('selectDevice'),
            subtitle: context.l10n.t('selectDeviceHint'),
          ),
        ),
      );
    }

    final tabIndex = ref.watch(selectedToolTabProvider);

    return DropTarget(
      onDragDone: (details) => _handleDrop(context, ref, device, details.files),
      child: DefaultTabController(
        key: ValueKey('${device.id}-$tabIndex'),
        length: 4,
        initialIndex: tabIndex,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SelectedDeviceHeader(device: device),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  TabBar(
                    onTap: (index) {
                      ref.read(selectedToolTabProvider.notifier).select(index);
                    },
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.tune),
                        text: context.l10n.t('control'),
                      ),
                      Tab(
                        icon: const Icon(Icons.apps),
                        text: context.l10n.t('apps'),
                      ),
                      Tab(
                        icon: const Icon(Icons.folder),
                        text: context.l10n.t('files'),
                      ),
                      Tab(
                        icon: const Icon(Icons.article),
                        text: context.l10n.t('logcat'),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 620,
                    child: TabBarView(
                      children: [
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: _ControlTab(
                            device: device,
                            sessions: sessions,
                          ),
                        ),
                        _AppsTab(device: device),
                        _FilesTab(device: device),
                        _LogcatTab(device: device),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleDrop(
    BuildContext context,
    WidgetRef ref,
    AdbDevice device,
    List<XFile> files,
  ) async {
    if (files.isEmpty) {
      return;
    }
    final appService = ref.read(appManagementServiceProvider);
    final fileService = ref.read(fileManagerServiceProvider);
    final remotePath = ref.read(remotePathProvider);

    for (final file in files) {
      final isApk = file.path.toLowerCase().endsWith('.apk');
      final result = isApk
          ? await appService.installApk(device.id, file.path)
          : await fileService.push(device.id, file.path, remotePath);
      if (!context.mounted) {
        return;
      }
      _showSnack(
        context,
        '${file.name}: ${result.message}',
        isError: !result.isSuccess,
      );
    }
    ref.invalidate(packagesProvider(device.id));
    ref.invalidate(
      remoteFilesProvider(
        RemoteDirectoryRequest(deviceId: device.id, path: remotePath),
      ),
    );
  }
}

class _SelectedDeviceHeader extends StatelessWidget {
  const _SelectedDeviceHeader({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.phone_android,
              size: 36,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(device.id),
                ],
              ),
            ),
            Chip(
              label: Text(device.status),
              avatar: Icon(
                device.isOnline ? Icons.check_circle : Icons.warning_amber,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlTab extends StatelessWidget {
  const _ControlTab({required this.device, required this.sessions});

  final AdbDevice device;
  final Map<String, ScrcpySession> sessions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScrcpyPanel(device: device, sessions: sessions),
        const SizedBox(height: 16),
        _QuickActionsPanel(device: device),
        const SizedBox(height: 16),
        _LayoutHelperPanel(device: device),
        const SizedBox(height: 16),
        _InfoActionsPanel(device: device),
      ],
    );
  }
}

class _ScrcpyPanel extends ConsumerWidget {
  const _ScrcpyPanel({required this.device, required this.sessions});

  final AdbDevice device;
  final Map<String, ScrcpySession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSessions = sessions.values
        .where((session) => session.deviceId == device.id)
        .toList(growable: false);

    return _ActionCard(
      title: context.l10n.t('scrcpyLauncher'),
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: Text(context.l10n.t('start')),
          onPressed: device.isOnline
              ? () => _startScrcpy(context, ref, device.id)
              : null,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.stop),
          label: Text(context.l10n.t('stopAll')),
          onPressed: activeSessions.isEmpty
              ? null
              : () => _stopSessions(context, ref, activeSessions),
        ),
        for (final session in activeSessions)
          InputChip(
            avatar: const Icon(Icons.cast_connected, size: 18),
            label: Text('PID ${session.pid}'),
            onDeleted: () => _stopSessions(context, ref, [session]),
          ),
      ],
    );
  }

  Future<void> _startScrcpy(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    try {
      final session = await ref
          .read(scrcpyServiceProvider)
          .start(deviceId: deviceId, options: const ScrcpyLaunchOptions());
      ref.read(scrcpySessionsProvider.notifier).add(session);
      if (context.mounted) {
        _showSnack(
          context,
          '${context.l10n.t('scrcpyStarted')}: PID ${session.pid}',
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showSnack(context, error.toString(), isError: true);
      }
    }
  }

  Future<void> _stopSessions(
    BuildContext context,
    WidgetRef ref,
    List<ScrcpySession> sessions,
  ) async {
    final service = ref.read(scrcpyServiceProvider);
    for (final session in sessions) {
      await service.stop(session.id);
    }
    ref
        .read(scrcpySessionsProvider.notifier)
        .removeAll(sessions.map((session) => session.id));
    if (context.mounted) {
      _showSnack(context, context.l10n.t('scrcpyStopped'));
    }
  }
}

class _QuickActionsPanel extends ConsumerWidget {
  const _QuickActionsPanel({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);

    return _ActionCard(
      title: context.l10n.t('deviceActions'),
      children: [
        _ActionButton(
          icon: Icons.keyboard,
          label: context.l10n.t('inputText'),
          onPressed: () => _showInputTextDialog(context, ref, device.id),
        ),
        _ActionButton(
          icon: Icons.home,
          label: context.l10n.t('home'),
          onPressed: () =>
              _runAdbAction(context, actions.keyEvent(device.id, 3)),
        ),
        _ActionButton(
          icon: Icons.arrow_back,
          label: context.l10n.t('back'),
          onPressed: () =>
              _runAdbAction(context, actions.keyEvent(device.id, 4)),
        ),
        _ActionButton(
          icon: Icons.power_settings_new,
          label: context.l10n.t('power'),
          onPressed: () =>
              _runAdbAction(context, actions.keyEvent(device.id, 26)),
        ),
        _ActionButton(
          icon: Icons.volume_up,
          label: context.l10n.t('volumeUp'),
          onPressed: () =>
              _runAdbAction(context, actions.keyEvent(device.id, 24)),
        ),
        _ActionButton(
          icon: Icons.volume_down,
          label: context.l10n.t('volumeDown'),
          onPressed: () =>
              _runAdbAction(context, actions.keyEvent(device.id, 25)),
        ),
        _ActionButton(
          icon: Icons.wifi,
          label: context.l10n.t('wifiOn'),
          onPressed: () =>
              _runAdbAction(context, actions.setWifi(device.id, true)),
        ),
        _ActionButton(
          icon: Icons.wifi_off,
          label: context.l10n.t('wifiOff'),
          onPressed: () =>
              _runAdbAction(context, actions.setWifi(device.id, false)),
        ),
      ],
    );
  }

  Future<void> _showInputTextDialog(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.t('inputText')),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: context.l10n.t('text')),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.t('cancel')),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: Text(context.l10n.t('send')),
              onPressed: () => Navigator.of(context).pop(controller.text),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (text == null || text.isEmpty || !context.mounted) {
      return;
    }
    await _runAdbAction(
      context,
      ref.read(deviceActionServiceProvider).inputText(deviceId, text),
    );
  }
}

class _LayoutHelperPanel extends ConsumerWidget {
  const _LayoutHelperPanel({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);

    return _ActionCard(
      title: context.l10n.t('layoutHelper'),
      children: [
        _ActionButton(
          icon: Icons.border_outer,
          label: context.l10n.t('boundsOn'),
          onPressed: () => _runAdbAction(
            context,
            actions.toggleLayoutBounds(device.id, true),
          ),
        ),
        _ActionButton(
          icon: Icons.border_clear,
          label: context.l10n.t('boundsOff'),
          onPressed: () => _runAdbAction(
            context,
            actions.toggleLayoutBounds(device.id, false),
          ),
        ),
        _ActionButton(
          icon: Icons.dark_mode,
          label: context.l10n.t('darkMode'),
          onPressed: () =>
              _runAdbAction(context, actions.setDarkMode(device.id, true)),
        ),
        _ActionButton(
          icon: Icons.light_mode,
          label: context.l10n.t('lightMode'),
          onPressed: () =>
              _runAdbAction(context, actions.setDarkMode(device.id, false)),
        ),
      ],
    );
  }
}

class _InfoActionsPanel extends ConsumerWidget {
  const _InfoActionsPanel({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);

    return _ActionCard(
      title: context.l10n.t('deviceInfo'),
      children: [
        _ActionButton(
          icon: Icons.badge_outlined,
          label: context.l10n.t('androidId'),
          onPressed: () =>
              _showAdbResult(context, actions.androidId(device.id)),
        ),
        _ActionButton(
          icon: Icons.info_outline,
          label: context.l10n.t('version'),
          onPressed: () =>
              _showAdbResult(context, actions.systemVersion(device.id)),
        ),
        _ActionButton(
          icon: Icons.center_focus_strong,
          label: context.l10n.t('focus'),
          onPressed: () =>
              _showAdbResult(context, actions.currentFocus(device.id)),
        ),
        _ActionButton(
          icon: Icons.restart_alt,
          label: context.l10n.t('reboot'),
          onPressed: () async {
            final confirmed = await _confirm(
              context,
              context.l10n.t('rebootDevice'),
            );
            if (confirmed && context.mounted) {
              await _runAdbAction(context, actions.reboot(device.id));
            }
          },
        ),
      ],
    );
  }
}

class _AppsTab extends ConsumerStatefulWidget {
  const _AppsTab({required this.device});

  final AdbDevice device;

  @override
  ConsumerState<_AppsTab> createState() => _AppsTabState();
}

class _AppsTabState extends ConsumerState<_AppsTab> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  String? _selectedPackage;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(packagesProvider(widget.device.id));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filterController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: context.l10n.t('filterPackage'),
                  ),
                  onChanged: (value) => setState(() => _filter = value),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.install_desktop),
                label: Text(context.l10n.t('installApk')),
                onPressed: _installApk,
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: context.l10n.t('refreshPackages'),
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.invalidate(packagesProvider(widget.device.id)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: packages.when(
              loading: () => _PanelMessage(
                icon: Icons.sync,
                title: context.l10n.t('loadingPackages'),
              ),
              error: (error, stackTrace) => _PanelMessage(
                icon: Icons.error_outline,
                title: context.l10n.t('packageListFailed'),
                subtitle: error.toString(),
              ),
              data: (items) {
                final filtered = _filterPackages(items);
                if (filtered.isEmpty) {
                  return _PanelMessage(
                    icon: Icons.apps_outlined,
                    title: context.l10n.t('noPackages'),
                  );
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final package = filtered[index];
                    final selected = package.name == _selectedPackage;
                    return ListTile(
                      selected: selected,
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      leading: const Icon(Icons.android),
                      title: Text(package.name),
                      onTap: () =>
                          setState(() => _selectedPackage = package.name),
                      trailing: selected
                          ? _PackageActions(
                              deviceId: widget.device.id,
                              packageName: package.name,
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<AdbPackage> _filterPackages(List<AdbPackage> items) {
    final filter = _filter.trim().toLowerCase();
    if (filter.isEmpty) {
      return items;
    }
    return items
        .where((package) => package.name.toLowerCase().contains(filter))
        .toList(growable: false);
  }

  Future<void> _installApk() async {
    const group = XTypeGroup(label: 'APK', extensions: ['apk']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || !mounted) {
      return;
    }
    final result = await ref
        .read(appManagementServiceProvider)
        .installApk(widget.device.id, file.path);
    if (!mounted) {
      return;
    }
    _showSnack(context, result.message, isError: !result.isSuccess);
    ref.invalidate(packagesProvider(widget.device.id));
  }
}

class _PackageActions extends ConsumerWidget {
  const _PackageActions({required this.deviceId, required this.packageName});

  final String deviceId;
  final String packageName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(appManagementServiceProvider);

    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: context.l10n.t('launch'),
          icon: const Icon(Icons.play_arrow),
          onPressed: () =>
              _runAdbAction(context, service.launch(deviceId, packageName)),
        ),
        IconButton(
          tooltip: context.l10n.t('forceStop'),
          icon: const Icon(Icons.stop),
          onPressed: () =>
              _runAdbAction(context, service.forceStop(deviceId, packageName)),
        ),
        IconButton(
          tooltip: context.l10n.t('packagePath'),
          icon: const Icon(Icons.route),
          onPressed: () => _showAdbResult(
            context,
            service.packagePath(deviceId, packageName),
          ),
        ),
        IconButton(
          tooltip: context.l10n.t('clearData'),
          icon: const Icon(Icons.cleaning_services_outlined),
          onPressed: () async {
            final confirmed = await _confirm(
              context,
              context.l10n
                  .t('clearDataFor')
                  .replaceAll('{package}', packageName),
            );
            if (confirmed && context.mounted) {
              await _runAdbAction(
                context,
                service.clearData(deviceId, packageName),
              );
            }
          },
        ),
        IconButton(
          tooltip: context.l10n.t('uninstall'),
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final confirmed = await _confirm(
              context,
              context.l10n
                  .t('uninstallPackage')
                  .replaceAll('{package}', packageName),
            );
            if (confirmed && context.mounted) {
              await _runAdbAction(
                context,
                service.uninstall(deviceId, packageName),
              );
              ref.invalidate(packagesProvider(deviceId));
            }
          },
        ),
      ],
    );
  }
}

class _FilesTab extends ConsumerWidget {
  const _FilesTab({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(remotePathProvider);
    final request = RemoteDirectoryRequest(deviceId: device.id, path: path);
    final files = ref.watch(remoteFilesProvider(request));

    return DropTarget(
      onDragDone: (details) => _pushFiles(context, ref, details.files, path),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: context.l10n.t('back'),
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: () {
                    ref.read(remotePathProvider.notifier).back();
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    path,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.t('refresh'),
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(remoteFilesProvider(request)),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: Text(context.l10n.t('push')),
                  onPressed: () async {
                    final file = await openFile();
                    if (file != null && context.mounted) {
                      await _pushFiles(context, ref, [file], path);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: files.when(
                loading: () => _PanelMessage(
                  icon: Icons.sync,
                  title: context.l10n.t('loadingFiles'),
                ),
                error: (error, stackTrace) => _PanelMessage(
                  icon: Icons.error_outline,
                  title: context.l10n.t('fileListFailed'),
                  subtitle: error.toString(),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return _PanelMessage(
                      icon: Icons.folder_open,
                      title: context.l10n.t('emptyFolder'),
                    );
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final file = items[index];
                      final remoteFilePath = _joinRemotePath(path, file.name);
                      return ListTile(
                        leading: Icon(_fileIcon(file)),
                        title: Text(file.name),
                        subtitle: Text(file.type.name),
                        onTap: file.isFolder
                            ? () => ref
                                  .read(remotePathProvider.notifier)
                                  .open(file.name)
                            : null,
                        trailing: file.isFolder
                            ? null
                            : _RemoteFileActions(
                                deviceId: device.id,
                                remotePath: remoteFilePath,
                                fileName: file.name,
                              ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pushFiles(
    BuildContext context,
    WidgetRef ref,
    List<XFile> files,
    String remotePath,
  ) async {
    final service = ref.read(fileManagerServiceProvider);
    for (final file in files) {
      if (file.path.toLowerCase().endsWith('.apk')) {
        final result = await ref
            .read(appManagementServiceProvider)
            .installApk(device.id, file.path);
        if (!context.mounted) {
          return;
        }
        _showSnack(
          context,
          '${file.name}: ${result.message}',
          isError: !result.isSuccess,
        );
        continue;
      }
      final result = await service.push(device.id, file.path, remotePath);
      if (!context.mounted) {
        return;
      }
      _showSnack(
        context,
        '${file.name}: ${result.message}',
        isError: !result.isSuccess,
      );
    }
    ref.invalidate(
      remoteFilesProvider(
        RemoteDirectoryRequest(deviceId: device.id, path: remotePath),
      ),
    );
  }
}

class _RemoteFileActions extends ConsumerWidget {
  const _RemoteFileActions({
    required this.deviceId,
    required this.remotePath,
    required this.fileName,
  });

  final String deviceId;
  final String remotePath;
  final String fileName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(fileManagerServiceProvider);

    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: context.l10n.t('pull'),
          icon: const Icon(Icons.download),
          onPressed: () async {
            final directory = await getDirectoryPath();
            if (directory == null || !context.mounted) {
              return;
            }
            final result = await service.pull(
              deviceId,
              remotePath,
              '$directory/$fileName',
            );
            if (context.mounted) {
              _showSnack(context, result.message, isError: !result.isSuccess);
            }
          },
        ),
        IconButton(
          tooltip: context.l10n.t('delete'),
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final confirmed = await _confirm(
              context,
              context.l10n.t('deleteFile').replaceAll('{file}', fileName),
            );
            if (!confirmed || !context.mounted) {
              return;
            }
            final result = await service.delete(deviceId, remotePath);
            if (context.mounted) {
              _showSnack(context, result.message, isError: !result.isSuccess);
            }
          },
        ),
      ],
    );
  }
}

class _LogcatTab extends ConsumerWidget {
  const _LogcatTab({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(logcatControllerProvider.notifier);
    final state = ref.watch(logcatControllerProvider);
    final lines = controller.visibleLines();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              FilledButton.icon(
                icon: Icon(state.isRunning ? Icons.stop : Icons.play_arrow),
                label: Text(
                  state.isRunning
                      ? context.l10n.t('stop')
                      : context.l10n.t('start'),
                ),
                onPressed: () {
                  state.isRunning
                      ? controller.stop()
                      : controller.start(device.id);
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.cleaning_services),
                label: Text(context.l10n.t('clear')),
                onPressed: controller.clear,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: context.l10n.t('filterLog'),
                  ),
                  onChanged: controller.setFilter,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xff101827),
                borderRadius: BorderRadius.circular(8),
              ),
              child: state.error != null
                  ? Text(
                      state.error!,
                      style: const TextStyle(color: Colors.redAccent),
                    )
                  : ListView.builder(
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        return SelectableText(
                          line,
                          style: TextStyle(
                            color: _logColor(line),
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.25,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: children),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _runAdbAction(
  BuildContext context,
  Future<AdbResult> future,
) async {
  final result = await future;
  if (!context.mounted) {
    return;
  }
  _showSnack(context, result.message, isError: !result.isSuccess);
}

Future<void> _showAdbResult(
  BuildContext context,
  Future<AdbResult> future,
) async {
  final result = await future;
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          result.isSuccess ? context.l10n.t('result') : context.l10n.t('error'),
        ),
        content: SelectableText(result.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.t('close')),
          ),
        ],
      );
    },
  );
}

Future<bool> _confirm(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(context.l10n.t('confirm')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.t('confirm')),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

void _showSnack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.inverseSurface,
    ),
  );
}

String _joinRemotePath(String base, String name) {
  final normalized = base.endsWith('/') ? base : '$base/';
  return '$normalized$name';
}

IconData _fileIcon(RemoteFile file) {
  return switch (file.type) {
    RemoteFileType.folder => Icons.folder,
    RemoteFileType.link => Icons.link,
    RemoteFileType.file => Icons.insert_drive_file_outlined,
  };
}

Color _logColor(String line) {
  if (line.contains(' E ') || line.contains('/E')) {
    return const Color(0xffff6b6b);
  }
  if (line.contains(' W ') || line.contains('/W')) {
    return const Color(0xffffd166);
  }
  if (line.contains(' I ') || line.contains('/I')) {
    return const Color(0xff67e8f9);
  }
  if (line.contains(' D ') || line.contains('/D')) {
    return const Color(0xff86efac);
  }
  return const Color(0xffe2e8f0);
}
