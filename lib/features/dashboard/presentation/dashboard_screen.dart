import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/adb/adb_result.dart';
import '../../../core/apps/adb_package.dart';
import '../../../core/device_info/device_overview.dart';
import '../../../core/files/remote_file.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/scrcpy_launch_options.dart';
import '../../../core/scrcpy/scrcpy_session.dart';

/// 桌面主面板，整合设备发现和工具区域。
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
      body: LayoutBuilder(
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
    );
  }
}

/// 紧凑布局下的 workspace 占位组件，从 Riverpod 状态重建内容。
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

/// 设置弹窗表单，用于切换语言和主题。
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

/// 设备发现卡片，提供 USB/TCP 连接入口。
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

  /// 输入 adb TCP 地址，连接后刷新设备列表。
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

/// 单台 adb 设备的可选列表项。
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

/// 承载选中设备全部工具的工作区。
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // 同一个 workspace 可能处在有界的桌面 Row 中，也可能处在无界的
        // 移动端 ListView 中，因此 tab 卡片需要不同的高度策略。
        final hasBoundedHeight = constraints.hasBoundedHeight;

        return DropTarget(
          onDragDone: (details) =>
              _handleDrop(context, ref, device, details.files),
          child: DefaultTabController(
            key: ValueKey('${device.id}-$tabIndex'),
            length: 5,
            initialIndex: tabIndex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SelectedDeviceHeader(device: device),
                const SizedBox(height: 16),
                if (hasBoundedHeight)
                  Expanded(
                    child: _ToolTabCard(device: device, sessions: sessions),
                  )
                else
                  SizedBox(
                    height: 620,
                    child: _ToolTabCard(device: device, sessions: sessions),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 处理桌面拖拽：APK 文件执行安装，其他文件执行上传。
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

/// Overview、Control、Apps、Files、Logcat 五个 tab 的卡片容器。
class _ToolTabCard extends ConsumerWidget {
  const _ToolTabCard({required this.device, required this.sessions});

  final AdbDevice device;
  final Map<String, ScrcpySession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(
        children: [
          TabBar(
            onTap: (index) {
              ref.read(selectedToolTabProvider.notifier).select(index);
            },
            tabs: [
              Tab(
                icon: const Icon(Icons.dashboard_outlined),
                text: context.l10n.t('overview'),
              ),
              Tab(
                icon: const Icon(Icons.tune),
                text: context.l10n.t('control'),
              ),
              Tab(icon: const Icon(Icons.apps), text: context.l10n.t('apps')),
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
          Expanded(
            child: TabBarView(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _OverviewTab(device: device),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _ControlTab(device: device, sessions: sessions),
                ),
                _AppsTab(device: device),
                _FilesTab(device: device),
                _LogcatTab(device: device),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 概览 tab，只承载选中设备的只读手机信息。
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context) {
    return _DeviceOverviewPanel(device: device);
  }
}

/// 展示当前设备身份和 adb 状态的头部区域。
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

/// 控制 tab，组合 scrcpy、快捷操作和调试辅助。
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
      ],
    );
  }
}

/// 只读手机概览面板，数据来自 adb 属性和 sysfs/proc 读取。
class _DeviceOverviewPanel extends ConsumerWidget {
  const _DeviceOverviewPanel({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(deviceOverviewProvider(device.id));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: overview.when(
          loading: () => _PanelMessage(
            icon: Icons.phone_android,
            title: context.l10n.t('overviewTitle'),
            subtitle: context.l10n.t('scanningDevices'),
          ),
          error: (error, stackTrace) => _PanelMessage(
            icon: Icons.error_outline,
            title: context.l10n.t('overviewTitle'),
            subtitle: error.toString(),
          ),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    context.l10n.t('overviewTitle'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: context.l10n.t('refresh'),
                    icon: const Icon(Icons.refresh),
                    onPressed: () =>
                        ref.invalidate(deviceOverviewProvider(device.id)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _OverviewGrid(items: _buildOverviewItems(context, data)),
            ],
          ),
        ),
      ),
    );
  }

  /// 将概览字段映射为图标、标签和值组件。
  List<_OverviewItemData> _buildOverviewItems(
    BuildContext context,
    DeviceOverview overview,
  ) {
    return [
      _OverviewItemData(
        icon: Icons.phone_android,
        label: context.l10n.t('deviceName'),
        value: overview.name,
      ),
      _OverviewItemData(
        icon: Icons.info,
        label: context.l10n.t('brand'),
        value: overview.brand,
      ),
      _OverviewItemData(
        icon: Icons.layers_outlined,
        label: context.l10n.t('model'),
        value: overview.model,
      ),
      _OverviewItemData(
        icon: Icons.pin_outlined,
        label: context.l10n.t('serial'),
        value: overview.serial,
      ),
      _OverviewItemData(
        icon: Icons.android,
        label: context.l10n.t('androidVersion'),
        value: overview.androidVersion,
      ),
      _OverviewItemData(
        icon: Icons.android,
        label: context.l10n.t('kernelVersion'),
        value: overview.kernelVersion,
      ),
      _OverviewItemData(
        icon: Icons.memory,
        label: context.l10n.t('processor'),
        value: overview.processor,
      ),
      _OverviewItemData(
        icon: Icons.storage,
        label: context.l10n.t('storage'),
        value: overview.storage,
      ),
      _OverviewItemData(
        icon: Icons.developer_board,
        label: context.l10n.t('memory'),
        value: overview.memory,
      ),
      _OverviewItemData(
        icon: Icons.stay_current_portrait,
        label: context.l10n.t('physicalResolution'),
        value: overview.physicalResolution,
      ),
      _OverviewItemData(
        icon: Icons.stay_current_portrait,
        label: context.l10n.t('resolution'),
        value: overview.resolution,
      ),
      _OverviewItemData(
        icon: Icons.text_fields,
        label: context.l10n.t('fontScale'),
        value: overview.fontScale,
      ),
      _OverviewItemData(
        icon: Icons.wifi,
        label: context.l10n.t('wifi'),
        value: overview.wifi,
      ),
      _OverviewItemData(
        icon: Icons.public,
        label: context.l10n.t('ipAddress'),
        value: overview.ipAddress,
      ),
      _OverviewItemData(
        icon: Icons.public,
        label: context.l10n.t('macAddress'),
        value: overview.macAddress,
      ),
    ];
  }
}

/// 概览条目的响应式网格。
class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.items});

  final List<_OverviewItemData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: 16,
          children: [
            for (final item in items) SizedBox(width: itemWidth, child: item),
          ],
        );
      },
    );
  }
}

/// 可点击复制的概览值单元。
class _OverviewItemData extends StatelessWidget {
  const _OverviewItemData({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // 只复制值，不复制标签，便于将 ID、型号、IP 等内容粘贴到其他工具。
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) {
          return;
        }
        _showSnack(
          context,
          context.l10n.t('copiedToClipboard').replaceAll('{label}', label),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// scrcpy 启动器和活跃会话控制区。
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

  /// 启动 scrcpy，并将返回的进程元数据记录到 Riverpod 状态。
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

  /// 停止选中的会话，并从 UI 中移除对应 Chip。
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

/// 常用一键设备操作，例如 key event、Wi-Fi 和文本输入。
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
          onPressed: () => _runAdbAction(context, actions.volumeUp(device.id)),
        ),
        _ActionButton(
          icon: Icons.volume_down,
          label: context.l10n.t('volumeDown'),
          onPressed: () =>
              _runAdbAction(context, actions.volumeDown(device.id)),
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

  /// 输入文本，并通过 adb input 发送到设备。
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

/// 面向开发调试的布局和主题辅助操作。
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

/// 应用 tab 使用 StatefulWidget，因为筛选和选中项属于本地 UI 状态。
class _AppsTab extends ConsumerStatefulWidget {
  const _AppsTab({required this.device});

  final AdbDevice device;

  @override
  ConsumerState<_AppsTab> createState() => _AppsTabState();
}

/// 展示已安装应用，并提供包级操作。
class _AppsTabState extends ConsumerState<_AppsTab> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  bool _hideSystemApps = true;
  bool _refreshingPackages = false;
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _hideSystemApps,
                    onChanged: (value) =>
                        setState(() => _hideSystemApps = value ?? true),
                  ),
                  Text(context.l10n.t('hideSystemApps')),
                ],
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
                onPressed: _refreshingPackages ? null : _refreshPackages,
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.l10n
                          .t('appCount')
                          .replaceAll('{visible}', '${filtered.length}')
                          .replaceAll('{total}', '${items.length}'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _PackageTable(
                        deviceId: widget.device.id,
                        packages: filtered,
                        selectedPackage: _selectedPackage,
                        onSelected: (packageName) =>
                            setState(() => _selectedPackage = packageName),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 对应用名和包名执行大小写不敏感筛选，并可隐藏系统应用。
  List<AdbPackage> _filterPackages(List<AdbPackage> items) {
    final filter = _filter.trim().toLowerCase();
    return items
        .where((package) => !_hideSystemApps || !package.system)
        .where((package) {
          if (filter.isEmpty) {
            return true;
          }
          return package.name.toLowerCase().contains(filter) ||
              package.displayName.toLowerCase().contains(filter) ||
              package.versionLabel.toLowerCase().contains(filter);
        })
        .toList(growable: false);
  }

  /// 打开宿主机文件选择器并安装选中的 APK。
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
    if (result.isSuccess) {
      await _refreshPackages();
    }
  }

  /// 手动刷新时强制读取手机数据，并覆盖本地应用列表缓存。
  Future<void> _refreshPackages() async {
    if (_refreshingPackages) {
      return;
    }
    setState(() => _refreshingPackages = true);
    try {
      await ref
          .read(appManagementServiceProvider)
          .refreshPackages(widget.device.id);
      ref.invalidate(packagesProvider(widget.device.id));
    } catch (error) {
      if (mounted) {
        _showSnack(context, error.toString(), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _refreshingPackages = false);
      }
    }
  }
}

/// 桌面风格的应用表格，包含元数据列和行操作。
class _PackageTable extends StatelessWidget {
  const _PackageTable({
    required this.deviceId,
    required this.packages,
    required this.selectedPackage,
    required this.onSelected,
  });

  final String deviceId;
  final List<AdbPackage> packages;
  final String? selectedPackage;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth > _packageTableMinWidth
            ? constraints.maxWidth
            : _packageTableMinWidth;
        final extraWidth = tableWidth - _packageTableMinWidth;
        final widths = _PackageTableWidths(
          appName: 260 + extraWidth * 0.45,
          packageName: 270 + extraWidth * 0.55,
        );

        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _PackageTableHeader(widths: widths),
                  Expanded(
                    child: ListView.builder(
                      itemCount: packages.length,
                      itemBuilder: (context, index) {
                        final package = packages[index];
                        return _PackageTableRow(
                          deviceId: deviceId,
                          package: package,
                          selected: package.name == selectedPackage,
                          widths: widths,
                          onSelected: () => onSelected(package.name),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

const _packageTableMinWidth = 1456.0;

class _PackageTableWidths {
  const _PackageTableWidths({required this.appName, required this.packageName});

  final double appName;
  final double packageName;
  double get version => 112;
  double get minSdk => 92;
  double get targetSdk => 128;
  double get storage => 124;
  double get status => 128;
  double get type => 148;
  double get actions => 194;
}

/// 表头行，所有列都明确宽度，避免短列标题被压成竖排。
class _PackageTableHeader extends StatelessWidget {
  const _PackageTableHeader({required this.widths});

  final _PackageTableWidths widths;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          _PackageHeaderCell(
            width: widths.appName,
            label: context.l10n.t('appName'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.packageName,
            label: context.l10n.t('packageName'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.version,
            label: context.l10n.t('version'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.minSdk,
            label: context.l10n.t('minSdkVersion'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.targetSdk,
            label: context.l10n.t('targetMaxSdk'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.storage,
            label: context.l10n.t('storageUsed'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.status,
            label: context.l10n.t('status'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.type,
            label: context.l10n.t('appType'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.actions,
            label: context.l10n.t('actions'),
            style: style,
          ),
        ],
      ),
    );
  }
}

class _PackageHeaderCell extends StatelessWidget {
  const _PackageHeaderCell({
    required this.width,
    required this.label,
    required this.style,
  });

  final double width;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return _PackageCell(
      width: width,
      child: Text(
        label,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 单个应用数据行。
class _PackageTableRow extends StatelessWidget {
  const _PackageTableRow({
    required this.deviceId,
    required this.package,
    required this.selected,
    required this.widths,
    required this.onSelected,
  });

  final String deviceId;
  final AdbPackage package;
  final bool selected;
  final _PackageTableWidths widths;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      child: Container(
        height: 72,
        color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
        child: Row(
          children: [
            _PackageCell(
              width: widths.appName,
              child: _AppNameCell(package: package),
            ),
            _PackageCell(
              width: widths.packageName,
              child: _TableText(package.name),
            ),
            _PackageCell(
              width: widths.version,
              child: _TableText(package.versionLabel),
            ),
            _PackageCell(
              width: widths.minSdk,
              child: Text(_sdkLabel(package.minSdk)),
            ),
            _PackageCell(
              width: widths.targetSdk,
              child: Text(_targetMaxSdkLabel(package)),
            ),
            _PackageCell(
              width: widths.storage,
              child: Text(package.storageLabel),
            ),
            _PackageCell(
              width: widths.status,
              child: _StatusChip(package: package),
            ),
            _PackageCell(
              width: widths.type,
              child: _AppTypeChip(package: package),
            ),
            _PackageCell(
              width: widths.actions,
              child: selected
                  ? _PackageActions(
                      deviceId: deviceId,
                      packageName: package.name,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageCell extends StatelessWidget {
  const _PackageCell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

/// 应用名称单元格，附带轻量类型图标。
class _AppNameCell extends StatelessWidget {
  const _AppNameCell({required this.package});

  final AdbPackage package;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = package.flutter
        ? Icons.flutter_dash
        : package.system
        ? Icons.settings_applications
        : Icons.android;
    final iconPath = package.iconLocalPath;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 28,
            height: 28,
            child: iconPath != null && File(iconPath).existsSync()
                ? Image.file(
                    File(iconPath),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        _FallbackAppIcon(
                          icon: icon,
                          system: package.system,
                          colorScheme: colorScheme,
                        ),
                  )
                : _FallbackAppIcon(
                    icon: icon,
                    system: package.system,
                    colorScheme: colorScheme,
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Tooltip(
            message: package.displayName,
            child: Text(
              package.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _FallbackAppIcon extends StatelessWidget {
  const _FallbackAppIcon({
    required this.icon,
    required this.system,
    required this.colorScheme,
  });

  final IconData icon;
  final bool system;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 14,
      backgroundColor: system
          ? colorScheme.surfaceContainerHighest
          : colorScheme.primaryContainer,
      child: Icon(
        icon,
        size: 18,
        color: system
            ? colorScheme.onSurfaceVariant
            : colorScheme.onPrimaryContainer,
      ),
    );
  }
}

/// 表格中的受限宽度文本，鼠标悬停时可查看完整值。
class _TableText extends StatelessWidget {
  const _TableText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: value,
      child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// 启用或停用状态徽标。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.package});

  final AdbPackage package;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        package.enabled
            ? context.l10n.t('enabled')
            : context.l10n.t('disabled'),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// 展示系统/用户应用和 Flutter/native 分类。
class _AppTypeChip extends StatelessWidget {
  const _AppTypeChip({required this.package});

  final AdbPackage package;

  @override
  Widget build(BuildContext context) {
    final labels = [
      package.system ? context.l10n.t('systemApp') : context.l10n.t('userApp'),
      package.flutter
          ? context.l10n.t('flutterApp')
          : context.l10n.t('nativeApp'),
    ];
    return _TableText(labels.join(' / '));
  }
}

String _sdkLabel(int? value) => value == null ? '-' : '$value';

String _targetMaxSdkLabel(AdbPackage package) {
  final target = _sdkLabel(package.targetSdk);
  final max = _sdkLabel(package.maxSdk);
  return max == '-' ? target : '$target / $max';
}

/// 当前选中应用行的内联操作按钮。
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
              final result = await service.uninstall(deviceId, packageName);
              if (context.mounted) {
                _showSnack(context, result.message, isError: !result.isSuccess);
              }
              if (result.isSuccess) {
                await service.refreshPackages(deviceId);
                ref.invalidate(packagesProvider(deviceId));
              }
            }
          },
        ),
      ],
    );
  }
}

/// `/sdcard/` 及其子目录的远程文件浏览器。
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

  /// 上传拖入或选中的文件；APK 会执行安装而不是复制。
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

/// 单个远程文件的下载和删除操作。
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

/// 实时 logcat 查看器，支持启动/停止、清空和文本筛选。
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

/// 用于承载一组相关操作按钮的小型复用卡片。
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

/// 操作面板中统一样式的 outlined 图标按钮。
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

/// dashboard 各面板复用的居中空态、加载态和错误态。
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

/// 等待 adb 命令完成，并通过 SnackBar 展示统一结果。
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

/// 执行 adb 命令，并在弹窗中展示完整输出。
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

/// 展示确认弹窗，用户直接关闭时默认返回 false。
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

/// 展示应用级短消息。
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

/// 拼接远程目录路径和文件名，不参与宿主机路径处理。
String _joinRemotePath(String base, String name) {
  final normalized = base.endsWith('/') ? base : '$base/';
  return '$normalized$name';
}

/// 根据解析出的远程文件类型选择图标。
IconData _fileIcon(RemoteFile file) {
  return switch (file.type) {
    RemoteFileType.folder => Icons.folder,
    RemoteFileType.link => Icons.link,
    RemoteFileType.file => Icons.insert_drive_file_outlined,
  };
}

/// 根据常见 logcat 标记应用简单的日志级别颜色。
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
