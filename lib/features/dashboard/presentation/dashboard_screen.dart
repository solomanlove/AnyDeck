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
import '../../../core/files/remote_file.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/scrcpy_launch_options.dart';
import '../../../core/scrcpy/scrcpy_session.dart';
import 'terminal_tab.dart';
import 'processes_tab.dart';
import 'webpages_tab.dart';

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
      appBarTitle = matchedDevice.displayName;
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          final workspace = _WorkspacePanel(
            selectedDevice: selectedDevice,
            sessions: sessions,
          );

          if (!compact) {
            return _WechatStyleShell(
              title: appBarTitle,
              selectedDevice: selectedDevice,
              child: selectedDevice == null
                  ? const _DashboardHomeContent()
                  : workspace,
            );
          }

          if (selectedDevice == null) {
            if (compact) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  _DeviceListPanel(),
                  SizedBox(height: 16),
                  _EmulatorListPanel(),
                ],
              );
            }

            final isEmulatorExpanded = ref.watch(_emulatorListExpandedProvider);

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Expanded(child: _DeviceListPanel()),
                  const SizedBox(height: 16),
                  if (isEmulatorExpanded)
                    const Expanded(child: _EmulatorListPanel())
                  else
                    const _EmulatorListPanel(),
                ],
              ),
            );
          }

          return Padding(padding: const EdgeInsets.all(16), child: workspace);
        },
      ),
    );
  }
}

class _WechatStyleShell extends ConsumerWidget {
  const _WechatStyleShell({
    required this.title,
    required this.selectedDevice,
    required this.child,
  });

  final String title;
  final AdbDevice? selectedDevice;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _PrimaryRail(selectedDevice: selectedDevice),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xfffbfbfc)),
            child: Column(
              children: [
                if (selectedDevice == null) _ContentTitleBar(title: title),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryRail extends ConsumerWidget {
  const _PrimaryRail({required this.selectedDevice});

  final AdbDevice? selectedDevice;

  static const double _fullToolRailMinHeight = 704;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTool = ref.watch(selectedToolTabProvider);
    final registeredDevices = ref.watch(deviceRegistryProvider);
    final hasOnlineDevice = registeredDevices.any((d) => d.isOnline);
    final canInteract = selectedDevice != null || hasOnlineDevice;
    final tools = [
      _RailToolItem(
        tabIndex: 0,
        icon: Icons.phone_android_outlined,
        label: context.l10n.t('overview'),
      ),
      _RailToolItem(
        tabIndex: 1,
        icon: Icons.tune,
        label: context.l10n.t('control'),
      ),
      _RailToolItem(
        tabIndex: 2,
        icon: Icons.apps_outlined,
        label: context.l10n.t('apps'),
      ),
      _RailToolItem(
        tabIndex: 3,
        icon: Icons.folder_outlined,
        label: context.l10n.t('files'),
      ),
      _RailToolItem(
        tabIndex: 4,
        icon: Icons.article_outlined,
        label: context.l10n.t('logcat'),
      ),
      _RailToolItem(
        tabIndex: 5,
        icon: Icons.terminal_outlined,
        label: context.l10n.t('terminal'),
      ),
      _RailToolItem(
        tabIndex: 6,
        icon: Icons.analytics_outlined,
        label: context.l10n.t('processes'),
      ),
      _RailToolItem(
        tabIndex: 7,
        icon: Icons.web_outlined,
        label: context.l10n.t('webpages'),
      ),
    ];

    void handleTap(int tabIndex) {
      var device = selectedDevice;
      if (device == null) {
        // Find the first online device
        RegisteredDevice? firstOnline;
        for (final d in registeredDevices) {
          if (d.isOnline) {
            firstOnline = d;
            break;
          }
        }
        if (firstOnline != null) {
          device = firstOnline.toAdbDevice;
          ref.read(userClearedDeviceSelectionProvider.notifier).state = false;
          ref.read(selectedDeviceProvider.notifier).select(device);
        }
      }
      if (device != null) {
        ref.read(selectedToolTabProvider.notifier).select(tabIndex);
      }
    }

    return Container(
      width: 76,
      color: const Color(0xffd8f3f5),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hideToolButtons =
                constraints.maxHeight < _fullToolRailMinHeight;

            return Column(
              children: [
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () {
                    ref
                            .read(userClearedDeviceSelectionProvider.notifier)
                            .state =
                        true;
                    ref.read(selectedDeviceProvider.notifier).clear();
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      width: 42,
                      height: 42,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Image(
                        image: AssetImage('assets/brand/app_logo.png'),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: hideToolButtons ? 18 : 28),
                if (hideToolButtons)
                  _RailMoreButton(
                    tools: tools,
                    hasSelectedDevice: selectedDevice != null,
                    selectedTool: selectedTool,
                    enabled: canInteract,
                    onSelected: handleTap,
                  )
                else
                  for (final tool in tools)
                    _RailButton(
                      icon: tool.icon,
                      selected:
                          selectedDevice != null &&
                          selectedTool == tool.tabIndex,
                      tooltip: tool.label,
                      onPressed: canInteract
                          ? () => handleTap(tool.tabIndex)
                          : null,
                    ),
                const Spacer(),
                _RailButton(
                  icon: Icons.settings_outlined,
                  tooltip: context.l10n.t('settings'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _SettingsDialog(),
                  ),
                ),
                const SizedBox(height: 18),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RailToolItem {
  const _RailToolItem({
    required this.tabIndex,
    required this.icon,
    required this.label,
  });

  final int tabIndex;
  final IconData icon;
  final String label;
}

class _RailMoreButton extends StatelessWidget {
  const _RailMoreButton({
    required this.tools,
    required this.hasSelectedDevice,
    required this.selectedTool,
    required this.enabled,
    required this.onSelected,
  });

  final List<_RailToolItem> tools;
  final bool hasSelectedDevice;
  final int selectedTool;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected =
        hasSelectedDevice && tools.any((tool) => tool.tabIndex == selectedTool);
    final color = selected ? const Color(0xff09c47c) : const Color(0xff5f6b6e);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: PopupMenuButton<int>(
        tooltip: context.l10n.t('moreTools'),
        onSelected: enabled ? onSelected : null,
        itemBuilder: (context) => [
          for (final tool in tools)
            PopupMenuItem<int>(
              value: tool.tabIndex,
              enabled: enabled,
              child: Row(
                children: [
                  Icon(
                    tool.icon,
                    size: 20,
                    color: tool.tabIndex == selectedTool
                        ? const Color(0xff09c47c)
                        : const Color(0xff5f6b6e),
                  ),
                  const SizedBox(width: 12),
                  Text(tool.label),
                ],
              ),
            ),
        ],
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.56)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.more_horiz, size: 28, color: color),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    this.selected = false,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xff09c47c) : const Color(0xff5f6b6e);

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: IconButton(
          icon: Icon(icon),
          color: color,
          iconSize: 28,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: selected
                ? Colors.white.withValues(alpha: 0.56)
                : Colors.transparent,
            disabledForegroundColor: const Color(0xff8b9a9e),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentTitleBar extends ConsumerWidget {
  const _ContentTitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffeceef1), width: 1)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xff202124),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: context.l10n.t('restartAdb'),
            icon: const Icon(Icons.adb),
            iconSize: 30,
            color: const Color(0xff5f6b6e),
            onPressed: () => _restartAdbServer(context, ref),
            style: IconButton.styleFrom(
              fixedSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardHomeContent extends StatelessWidget {
  const _DashboardHomeContent();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        _DeviceListPanel(),
        SizedBox(height: 16),
        _EmulatorListPanel(),
      ],
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
            const SizedBox(height: 8),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(context.l10n.t('authorInfo')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const _AuthorInfoDialog(),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(context.l10n.t('softwareManual')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const _SoftwareManualDialog(),
              ),
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

/// 作者信息弹窗，保持设置页内的轻量信息入口。
class _AuthorInfoDialog extends StatelessWidget {
  const _AuthorInfoDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.t('authorInfo')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoLine(
              label: context.l10n.t('authorNameLabel'),
              value: context.l10n.t('authorName'),
            ),
            const SizedBox(height: 8),
            _InfoLine(
              label: context.l10n.t('authorRoleLabel'),
              value: context.l10n.t('authorRole'),
            ),
            const SizedBox(height: 16),
            Text(context.l10n.t('authorDescription')),
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

/// 软件说明书弹窗，覆盖启动前准备和常用调试流程。
class _SoftwareManualDialog extends StatelessWidget {
  const _SoftwareManualDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.t('softwareManual')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ManualSection(
                title: context.l10n.t('softwareOverviewTitle'),
                body: context.l10n.t('softwareOverview'),
              ),
              _ManualSection(
                title: context.l10n.t('softwareRequirementsTitle'),
                body: context.l10n.t('softwareRequirements'),
              ),
              _ManualSection(
                title: context.l10n.t('softwareWorkflowTitle'),
                body: context.l10n.t('softwareWorkflow'),
              ),
              _ManualSection(
                title: context.l10n.t('softwareNoticeTitle'),
                body: context.l10n.t('softwareNotice'),
              ),
            ],
          ),
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

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 72, child: Text(label, style: textTheme.bodyMedium)),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ManualSection extends StatelessWidget {
  const _ManualSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(body),
        ],
      ),
    );
  }
}

/// 设备发现卡片，已重构为响应式表格形式。
class _DeviceListPanel extends ConsumerStatefulWidget {
  const _DeviceListPanel();

  @override
  ConsumerState<_DeviceListPanel> createState() => _DeviceListPanelState();
}

class _DeviceListPanelState extends ConsumerState<_DeviceListPanel> {
  String _sortColumn = 'id';
  bool _sortAscending = true;

  void _toggleSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  Widget _getSortIcon(String column) {
    if (_sortColumn != column) {
      return const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Icon(Icons.unfold_more, size: 14, color: Colors.grey),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        _sortAscending ? Icons.expand_less : Icons.expand_more,
        size: 14,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDevicesAsync = ref.watch(devicesProvider);
    final items = ref.watch(deviceRegistryProvider);

    // Sort items
    final sortedItems = List<RegisteredDevice>.from(items);
    sortedItems.sort((a, b) {
      // 已经连接的设备自动置顶 (Online devices always at the top)
      if (a.isOnline && !b.isOnline) return -1;
      if (!a.isOnline && b.isOnline) return 1;

      int cmp = 0;
      if (_sortColumn == 'id') {
        cmp = a.id.compareTo(b.id);
      } else if (_sortColumn == 'name') {
        cmp = a.displayName.compareTo(b.displayName);
      } else if (_sortColumn == 'status') {
        cmp = a.status.compareTo(b.status);
      }
      return _sortAscending ? cmp : -cmp;
    });

    final selectedCount = items.where((d) => d.isChecked).length;
    final allChecked = items.isNotEmpty && selectedCount == items.length;
    final hasChecked = selectedCount > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact = constraints.maxWidth < 600;
        final bool hasBoundedHeight = constraints.hasBoundedHeight;

        Widget contentWidget;
        if (activeDevicesAsync.hasError && items.isEmpty) {
          contentWidget = Center(
            child: _PanelMessage(
              icon: Icons.error_outline,
              title: context.l10n.t('adbUnavailable'),
              subtitle: activeDevicesAsync.error.toString(),
            ),
          );
        } else if (activeDevicesAsync.isLoading && items.isEmpty) {
          contentWidget = Center(
            child: _PanelMessage(
              icon: Icons.sync,
              title: context.l10n.t('scanningDevices'),
            ),
          );
        } else if (sortedItems.isEmpty) {
          contentWidget = Center(
            child: _PanelMessage(
              icon: Icons.usb_off_outlined,
              title: context.l10n.t('noDevices'),
              subtitle: context.l10n.t('connectUsbOrTcp'),
            ),
          );
        } else {
          contentWidget = ListView.separated(
            shrinkWrap: !hasBoundedHeight,
            physics: hasBoundedHeight
                ? null
                : const NeverScrollableScrollPhysics(),
            itemCount: sortedItems.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
            itemBuilder: (context, index) {
              final device = sortedItems[index];
              final isSelected =
                  ref.watch(selectedDeviceProvider)?.id == device.id;

              return Material(
                color: isSelected
                    ? Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.4)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () {
                    ref
                            .read(userClearedDeviceSelectionProvider.notifier)
                            .state =
                        false;
                    ref
                        .read(selectedDeviceProvider.notifier)
                        .select(device.toAdbDevice);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        if (!isCompact) ...[
                          SizedBox(
                            width: 45,
                            child: Checkbox(
                              value: device.isChecked,
                              onChanged: (val) {
                                ref
                                    .read(deviceRegistryProvider.notifier)
                                    .toggleCheck(device.id);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],

                        const SizedBox(width: 10),
                        // 设备标识：展示合并后的连接/序列标识，名称列单独保留可编辑别名。
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info,
                                color: Color(0xFF26A69A),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  device.connectionMethodDisplay,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (device.connections.isNotEmpty
                                  ? device.connections.any(
                                      (c) =>
                                          !(c.contains(':') ||
                                              c.contains('.') ||
                                              c == '127.0.0.1'),
                                    )
                                  : !device.isNetwork) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.usb,
                                  color: Color(0xFF26A69A),
                                  size: 16,
                                ),
                              ],
                              if (device.connections.isNotEmpty
                                  ? device.connections.any(
                                      (c) =>
                                          c.contains(':') ||
                                          c.contains('.') ||
                                          c == '127.0.0.1',
                                    )
                                  : device.isNetwork) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.wifi,
                                  color: Color(0xFF26A69A),
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // 设备名称：可编辑的用户别名，未设置时回退到 adb model/id。
                        Expanded(
                          flex: 3,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFFC8E6C9),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    device.displayName,
                                    style: const TextStyle(
                                      color: Color(0xFF2E7D32),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 14),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                splashRadius: 16,
                                onPressed: () =>
                                    _showRenameDialog(context, device),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Status Badge
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusBgColor(device.status),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getStatusText(context, device.status),
                                style: TextStyle(
                                  color: _getStatusTextColor(device.status),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Actions
                        Expanded(
                          flex: 2,
                          child: Row(
                            children: [
                              if (device.isNetwork) ...[
                                if (device.isOnline)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.link_off,
                                      color: Colors.red,
                                    ),
                                    tooltip: context.l10n.t('disconnect'),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _runAdbAction(
                                      context,
                                      ref,
                                      ref
                                          .read(deviceRegistryProvider.notifier)
                                          .disconnectDevice(device.id),
                                    ),
                                  )
                                else
                                  IconButton(
                                    icon: const Icon(
                                      Icons.link,
                                      color: Colors.green,
                                    ),
                                    tooltip: context.l10n.t('connect'),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _runAdbAction(
                                      context,
                                      ref,
                                      ref
                                          .read(deviceRegistryProvider.notifier)
                                          .connectDevice(device.id),
                                    ),
                                  ),
                                const SizedBox(width: 8),
                              ],
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                tooltip: context.l10n.t('delete'),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => ref
                                    .read(deviceRegistryProvider.notifier)
                                    .removeDevice(device.id),
                              ),
                            ],
                          ),
                        ),
                        if (!isCompact) ...[
                          const SizedBox(width: 10),
                          const SizedBox(
                            width: 40,
                            child: Icon(
                              Icons.chevron_right,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }

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
                      message: context.l10n.t('deleteSelectedDevices'),
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.delete_sweep_outlined),
                        color: Colors.redAccent,
                        onPressed: hasChecked
                            ? () =>
                                  _deleteSelectedDevices(context, selectedCount)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: context.l10n.t('connectTcp'),
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.add_link),
                        onPressed: () => _showConnectDialog(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: context.l10n.t('pairDeviceTitle'),
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.sensors),
                        onPressed: () => _showPairingDialog(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: context.l10n.t('refreshDevices'),
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => _refreshDevices(context, ref),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Table Header Row
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (!isCompact) ...[
                        SizedBox(
                          width: 45,
                          child: Checkbox(
                            tristate: true,
                            value: hasChecked && !allChecked
                                ? null
                                : allChecked,
                            onChanged: (_) {
                              ref
                                  .read(deviceRegistryProvider.notifier)
                                  .toggleAll(!allChecked);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      // Identifier header
                      Expanded(
                        flex: 3,
                        child: InkWell(
                          onTap: () => _toggleSort('id'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  context.l10n.t('deviceIdentifier'),
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                _getSortIcon('id'),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Name header
                      Expanded(
                        flex: 3,
                        child: InkWell(
                          onTap: () => _toggleSort('name'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  context.l10n.t('deviceNameCol'),
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                _getSortIcon('name'),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Status header
                      Expanded(
                        flex: 2,
                        child: InkWell(
                          onTap: () => _toggleSort('status'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  context.l10n.t('deviceStatusCol'),
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                _getSortIcon('status'),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Actions header
                      Expanded(
                        flex: 2,
                        child: Text(
                          context.l10n.t('deviceActionsCol'),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (!isCompact) ...[
                        const SizedBox(width: 10),
                        const SizedBox(
                          width: 40,
                          child: Icon(
                            Icons.settings,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Table Body Row
                if (hasBoundedHeight)
                  Expanded(child: contentWidget)
                else
                  contentWidget,
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteSelectedDevices(
    BuildContext context,
    int selectedCount,
  ) async {
    final confirmed = await _confirm(
      context,
      context.l10n
          .t('deleteSelectedDevicesConfirm')
          .replaceAll('{count}', '$selectedCount'),
    );
    if (!context.mounted || !confirmed) {
      return;
    }

    await ref.read(deviceRegistryProvider.notifier).removeCheckedDevices();
    if (!context.mounted) {
      return;
    }

    _showSnack(
      context,
      context.l10n
          .t('selectedDevicesDeleted')
          .replaceAll('{count}', '$selectedCount'),
    );
  }

  Color _getStatusBgColor(String status) {
    return switch (status) {
      'device' => const Color(0xFFE8F5E9),
      'unauthorized' => const Color(0xFFFFF3E0),
      'offline' => const Color(0xFFF5F5F5),
      _ => const Color(0xFFF5F5F5),
    };
  }

  Color _getStatusTextColor(String status) {
    return switch (status) {
      'device' => const Color(0xFF2E7D32),
      'unauthorized' => const Color(0xFFE65100),
      'offline' => const Color(0xFF9E9E9E),
      _ => const Color(0xFF9E9E9E),
    };
  }

  String _getStatusText(BuildContext context, String status) {
    return switch (status) {
      'device' => context.l10n.t('deviceOnline'),
      'unauthorized' => context.l10n.t('deviceUnauthorized'),
      'offline' => context.l10n.t('deviceOffline'),
      _ => status,
    };
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    RegisteredDevice device,
  ) async {
    final controller = TextEditingController(
      text: device.customName ?? device.model ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.t('editDeviceName')),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.l10n.t('enterDeviceName'),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(context.l10n.t('confirm')),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (name != null && context.mounted) {
      await ref.read(deviceRegistryProvider.notifier).setAlias(device.id, name);
    }
  }

  Future<void> _showConnectDialog(BuildContext context) async {
    await _showConnectDeviceDialog(context, ref);
  }

  void _showPairingDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _DevicePairingDialog(),
    );
  }
}

class _EmulatorListPanel extends ConsumerStatefulWidget {
  const _EmulatorListPanel();

  @override
  ConsumerState<_EmulatorListPanel> createState() => _EmulatorListPanelState();
}

class _EmulatorListPanelState extends ConsumerState<_EmulatorListPanel> {
  String _sortColumn = 'name';
  bool _sortAscending = true;

  void _toggleSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  Widget _getSortIcon(String column) {
    if (_sortColumn != column) {
      return const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Icon(Icons.unfold_more, size: 14, color: Colors.grey),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        _sortAscending ? Icons.expand_less : Icons.expand_more,
        size: 14,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isExpanded = ref.watch(_emulatorListExpandedProvider);
    final emulatorsAsync = ref.watch(emulatorListProvider);
    final runningEmulatorsAsync = ref.watch(runningEmulatorsProvider);
    final startingEmulators = ref.watch(startingEmulatorsProvider);

    final emulators = emulatorsAsync.value ?? [];
    final runningMap = runningEmulatorsAsync.value ?? {};

    // 组合数据
    final items = emulators.map((name) {
      final isStarting = startingEmulators.contains(name);
      final runningDeviceId = runningMap[name];
      final isRunning = runningDeviceId != null;

      String status = 'stopped';
      if (isRunning) status = 'running';
      if (isStarting) status = 'starting';

      return _EmulatorItem(
        name: name,
        status: status,
        deviceId: runningDeviceId,
      );
    }).toList();

    // 排序
    items.sort((a, b) {
      // 运行中和启动中的置顶
      final aActive = a.status != 'stopped';
      final bActive = b.status != 'stopped';
      if (aActive && !bActive) return -1;
      if (!aActive && bActive) return 1;

      int cmp = 0;
      if (_sortColumn == 'name') {
        cmp = a.name.compareTo(b.name);
      } else if (_sortColumn == 'status') {
        cmp = a.status.compareTo(b.status);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isCompact = constraints.maxWidth < 600;
        final bool hasBoundedHeight = constraints.hasBoundedHeight;

        Widget contentWidget;
        if (emulatorsAsync.hasError) {
          contentWidget = Center(
            child: _PanelMessage(
              icon: Icons.error_outline,
              title: context.l10n.t('noEmulators'),
              subtitle: emulatorsAsync.error.toString(),
            ),
          );
        } else if (emulatorsAsync.isLoading && emulators.isEmpty) {
          contentWidget = Center(
            child: _PanelMessage(
              icon: Icons.sync,
              title: context.l10n.t('scanningEmulators'),
            ),
          );
        } else if (items.isEmpty) {
          contentWidget = Center(
            child: _PanelMessage(
              icon: Icons.devices_other_outlined,
              title: context.l10n.t('noEmulators'),
              subtitle: context.l10n.t('createEmulatorHint'),
            ),
          );
        } else {
          contentWidget = ListView.separated(
            shrinkWrap: !hasBoundedHeight,
            physics: hasBoundedHeight
                ? null
                : const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
            itemBuilder: (context, index) {
              final item = items[index];

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    // Emulator Name
                    Expanded(
                      flex: 5,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.tablet_android,
                            color: Color(0xFF26A69A),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.name.replaceAll('_', ' '),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Status Badge
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusBgColor(item.status),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getStatusText(context, item.status),
                            style: TextStyle(
                              color: _getStatusTextColor(item.status),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Actions
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          if (item.status == 'running')
                            IconButton(
                              icon: const Icon(
                                Icons.stop_circle_outlined,
                                color: Colors.red,
                              ),
                              tooltip: context.l10n.t('stop'),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _stopEmulator(context, item),
                            )
                          else if (item.status == 'stopped')
                            IconButton(
                              icon: const Icon(
                                Icons.play_circle_outline,
                                color: Colors.green,
                              ),
                              tooltip: context.l10n.t('start'),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () =>
                                  _startEmulator(context, item.name),
                            )
                          else
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                    if (!isCompact) ...[
                      const SizedBox(width: 10),
                      const SizedBox(width: 40),
                    ],
                  ],
                ),
              );
            },
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            ref
                                .read(_emulatorListExpandedProvider.notifier)
                                .toggle();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  context.l10n.t('emulators'),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(width: 8),
                                AnimatedRotation(
                                  turns: isExpanded ? 0.5 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: const Icon(Icons.keyboard_arrow_down),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          ref.invalidate(emulatorListProvider);
                          ref.invalidate(runningEmulatorsProvider);
                        },
                      ),
                    ],
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 16),
                    // Table Header Row
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).dividerColor,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Name header
                          Expanded(
                            flex: 5,
                            child: InkWell(
                              onTap: () => _toggleSort('name'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      context.l10n.t('emulatorNameCol'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    _getSortIcon('name'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Status header
                          Expanded(
                            flex: 3,
                            child: InkWell(
                              onTap: () => _toggleSort('status'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      context.l10n.t('emulatorStatusCol'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    _getSortIcon('status'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Actions header
                          Expanded(
                            flex: 2,
                            child: Text(
                              context.l10n.t('emulatorActionsCol'),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (!isCompact) ...[
                            const SizedBox(width: 10),
                            const SizedBox(width: 40),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Table Body Row
                    if (hasBoundedHeight)
                      Expanded(child: contentWidget)
                    else
                      contentWidget,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getStatusBgColor(String status) {
    return switch (status) {
      'running' => const Color(0xFFE8F5E9),
      'starting' => const Color(0xFFFFF3E0),
      'stopped' => const Color(0xFFF5F5F5),
      _ => const Color(0xFFF5F5F5),
    };
  }

  Color _getStatusTextColor(String status) {
    return switch (status) {
      'running' => const Color(0xFF2E7D32),
      'starting' => const Color(0xFFE65100),
      'stopped' => const Color(0xFF9E9E9E),
      _ => const Color(0xFF9E9E9E),
    };
  }

  String _getStatusText(BuildContext context, String status) {
    return switch (status) {
      'running' => context.l10n.t('emulatorRunning'),
      'starting' => context.l10n.t('emulatorStarting'),
      'stopped' => context.l10n.t('emulatorStopped'),
      _ => status,
    };
  }

  Future<void> _startEmulator(BuildContext context, String avdName) async {
    ref.read(startingEmulatorsProvider.notifier).start(avdName);

    final success = await ref
        .read(emulatorServiceProvider)
        .startEmulator(avdName);
    if (!context.mounted) return;

    if (success) {
      _showSnack(context, context.l10n.t('startSuccess'));
    } else {
      ref.read(startingEmulatorsProvider.notifier).stopStarting(avdName);
      _showSnack(context, '启动模拟器失败', isError: true);
    }
  }

  Future<void> _stopEmulator(BuildContext context, _EmulatorItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.t('confirm')),
          content: Text(
            context.l10n
                .t('stopEmulatorConfirm')
                .replaceAll('{emulator}', item.name.replaceAll('_', ' ')),
          ),
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

    if (confirm != true || !context.mounted) return;

    if (item.deviceId == null) {
      _showSnack(context, context.l10n.t('stopFailed'), isError: true);
      return;
    }

    final adb = ref.read(adbServiceProvider);
    final result = await adb.run(['-s', item.deviceId!, 'emu', 'kill']);
    if (!context.mounted) return;

    if (result.isSuccess) {
      _showSnack(context, context.l10n.t('stopSuccess'));
      ref.invalidate(devicesProvider);
    } else {
      _showSnack(
        context,
        '${context.l10n.t('stopFailed')}: ${result.message}',
        isError: true,
      );
    }
  }
}

class _EmulatorItem {
  const _EmulatorItem({
    required this.name,
    required this.status,
    this.deviceId,
  });

  final String name;
  final String status;
  final String? deviceId;
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
      return const SizedBox.shrink();
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SelectedDeviceHeader(device: device, sessions: sessions),
              const SizedBox(height: 16),
              if (hasBoundedHeight)
                Expanded(
                  child: _ToolContentCard(
                    device: device,
                    sessions: sessions,
                    tabIndex: tabIndex,
                  ),
                )
              else
                SizedBox(
                  height: 800,
                  child: _ToolContentCard(
                    device: device,
                    sessions: sessions,
                    tabIndex: tabIndex,
                  ),
                ),
            ],
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

class _ToolContentCard extends StatelessWidget {
  const _ToolContentCard({
    required this.device,
    required this.sessions,
    required this.tabIndex,
  });

  final AdbDevice device;
  final Map<String, ScrcpySession> sessions;
  final int tabIndex;

  @override
  Widget build(BuildContext context) {
    final child = switch (tabIndex) {
      0 => _ToolTabScrollView(child: _OverviewTab(device: device)),
      1 => _ToolTabScrollView(
        child: _ControlTab(device: device, sessions: sessions),
      ),
      2 => _AppsTab(device: device),
      3 => _FilesTab(device: device),
      4 => _LogcatTab(device: device),
      5 => Padding(
        padding: const EdgeInsets.all(16),
        child: TerminalTab(device: device),
      ),
      6 => ProcessesTab(device: device),
      _ => WebpagesTab(device: device),
    };

    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          children: [
            _ToolContentHeader(tabIndex: tabIndex),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _ToolContentHeader extends StatelessWidget {
  const _ToolContentHeader({required this.tabIndex});

  final int tabIndex;

  @override
  Widget build(BuildContext context) {
    final data = switch (tabIndex) {
      0 => (Icons.dashboard_outlined, context.l10n.t('overview')),
      1 => (Icons.tune, context.l10n.t('control')),
      2 => (Icons.apps_outlined, context.l10n.t('apps')),
      3 => (Icons.folder_outlined, context.l10n.t('files')),
      4 => (Icons.article_outlined, context.l10n.t('logcat')),
      5 => (Icons.terminal_outlined, context.l10n.t('terminal')),
      6 => (Icons.analytics_outlined, context.l10n.t('processes')),
      _ => (Icons.web_outlined, context.l10n.t('webpages')),
    };

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffeceef1), width: 1)),
      ),
      child: Row(
        children: [
          Icon(data.$1, size: 22, color: const Color(0xff09c47c)),
          const SizedBox(width: 10),
          Text(
            data.$2,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xff202124),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tab 内容统一使用内部滚动，避免外层页面滚动抢占桌面端滚轮事件。
class _ToolTabScrollView extends StatefulWidget {
  const _ToolTabScrollView({required this.child});

  final Widget child;

  @override
  State<_ToolTabScrollView> createState() => _ToolTabScrollViewState();
}

class _ToolTabScrollViewState extends State<_ToolTabScrollView> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        primary: false,
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        child: widget.child,
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

/// 展示当前设备身份和 adb 状态的顶部单行 Header，同时包含 scrcpy 投屏控制。
class _SelectedDeviceHeader extends ConsumerWidget {
  const _SelectedDeviceHeader({required this.device, this.sessions = const {}});

  final AdbDevice device;
  final Map<String, ScrcpySession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSessions = sessions.values
        .where((session) => session.deviceId == device.id)
        .toList(growable: false);

    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffeceef1), width: 1)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.phone_android,
            size: 38,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xff202124),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    device.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xff202124),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            fit: FlexFit.loose,
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // scrcpy 投屏控制区
                    FilledButton.icon(
                      icon: const Icon(Icons.cast, size: 18),
                      label: Text(context.l10n.t('start')),
                      onPressed: device.isOnline
                          ? () => _startScrcpy(context, ref, device.id)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    if (activeSessions.isNotEmpty) ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.stop, size: 18),
                        label: Text(context.l10n.t('stopAll')),
                        onPressed: () =>
                            _stopSessions(context, ref, activeSessions),
                      ),
                      const SizedBox(width: 8),
                      for (final session in activeSessions) ...[
                        InputChip(
                          avatar: const Icon(Icons.cast_connected, size: 18),
                          label: Text('PID ${session.pid}'),
                          onDeleted: () =>
                              _stopSessions(context, ref, [session]),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ],
                    Chip(
                      label: Text(device.status),
                      avatar: Icon(
                        device.isOnline
                            ? Icons.check_circle
                            : Icons.warning_amber,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: context.l10n.t('close'),
            onPressed: () {
              ref.read(userClearedDeviceSelectionProvider.notifier).state =
                  true;
              ref.read(selectedDeviceProvider.notifier).clear();
            },
          ),
        ],
      ),
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

/// 控制 tab，组合快捷操作和调试辅助（scrcpy 已移至设备头部）。
class _ControlTab extends StatelessWidget {
  const _ControlTab({required this.device, required this.sessions});

  final AdbDevice device;
  final Map<String, ScrcpySession> sessions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
    final overview = device.isOnline
        ? ref.watch(
            deviceOverviewProvider(device.id).select(
              (value) => value.whenData<DeviceOverview?>((data) => data),
            ),
          )
        : ref.watch(cachedDeviceOverviewProvider(device.id));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: overview.when(
          loading: () => _PanelMessage(
            icon: Icons.phone_android,
            title: context.l10n.t('overviewTitle'),
            subtitle: device.isOnline
                ? context.l10n.t('scanningDevices')
                : context.l10n.t('loadingCachedOverview'),
          ),
          error: (error, stackTrace) => _PanelMessage(
            icon: Icons.error_outline,
            title: context.l10n.t('overviewTitle'),
            subtitle: error.toString(),
          ),
          data: (data) => data == null
              ? _PanelMessage(
                  icon: Icons.info_outline,
                  title: context.l10n.t('overviewTitle'),
                  subtitle: context.l10n.t('noCachedOverview'),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          context.l10n.t('overviewTitle'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _OverviewShortcutActions(device: device),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: context.l10n.t('refresh'),
                          icon: const Icon(Icons.refresh),
                          onPressed: () => device.isOnline
                              ? ref.invalidate(
                                  deviceOverviewProvider(device.id),
                                )
                              : ref.invalidate(
                                  cachedDeviceOverviewProvider(device.id),
                                ),
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
        icon: Icons.badge_outlined,
        label: context.l10n.t('androidId'),
        value: overview.androidId,
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
        icon: Icons.blur_on,
        label: context.l10n.t('logicalDensity'),
        value: overview.logicalDensity,
      ),
      _OverviewItemData(
        icon: Icons.speed,
        label: context.l10n.t('refreshRate'),
        value: overview.refreshRate,
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

/// 概览页右上角常用设备功能入口，保持只读信息页也能快速操作设备。
class _OverviewShortcutActions extends ConsumerWidget {
  const _OverviewShortcutActions({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);
    final enabled = device.isOnline;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xff374151),
            disabledForegroundColor: const Color(0xffa9b0bc),
            minimumSize: const Size(36, 36),
            fixedSize: const Size(36, 36),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: context.l10n.t('home'),
              icon: const Icon(Icons.home_outlined),
              onPressed: enabled
                  ? () => _runAdbAction(
                      context,
                      ref,
                      actions.keyEvent(device.id, 3),
                    )
                  : null,
            ),
            IconButton(
              tooltip: context.l10n.t('back'),
              icon: const Icon(Icons.arrow_back),
              onPressed: enabled
                  ? () => _runAdbAction(
                      context,
                      ref,
                      actions.keyEvent(device.id, 4),
                    )
                  : null,
            ),
            IconButton(
              tooltip: context.l10n.t('power'),
              icon: const Icon(Icons.power_settings_new),
              onPressed: enabled
                  ? () => _runAdbAction(
                      context,
                      ref,
                      actions.keyEvent(device.id, 26),
                    )
                  : null,
            ),
            IconButton(
              tooltip: context.l10n.t('notificationBar'),
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: enabled
                  ? () => _runAdbAction(
                      context,
                      ref,
                      actions.openNotificationBar(device.id),
                    )
                  : null,
            ),
            IconButton(
              tooltip: context.l10n.t('focus'),
              icon: const Icon(Icons.center_focus_strong),
              onPressed: enabled
                  ? () => _showAdbResult(
                      context,
                      ref,
                      actions.currentFocus(device.id),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
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
              _runAdbAction(context, ref, actions.keyEvent(device.id, 3)),
        ),
        _ActionButton(
          icon: Icons.arrow_back,
          label: context.l10n.t('back'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.keyEvent(device.id, 4)),
        ),
        _ActionButton(
          icon: Icons.power_settings_new,
          label: context.l10n.t('power'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.keyEvent(device.id, 26)),
        ),
        _ActionButton(
          icon: Icons.volume_up,
          label: context.l10n.t('volumeUp'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.volumeUp(device.id)),
        ),
        _ActionButton(
          icon: Icons.volume_down,
          label: context.l10n.t('volumeDown'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.volumeDown(device.id)),
        ),
        _ToggleActionButton(
          iconOn: Icons.wifi,
          iconOff: Icons.wifi_off,
          label: context.l10n.t('wifiToggle'),
          onToggle: (on) =>
              _runAdbAction(context, ref, actions.setWifi(device.id, on)),
        ),
        _ActionButton(
          icon: Icons.menu,
          label: context.l10n.t('menuKey'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.menuKey(device.id)),
        ),
        _ActionButton(
          icon: Icons.notifications_active,
          label: context.l10n.t('notificationBar'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openNotificationBar(device.id),
          ),
        ),
        _ToggleActionButton(
          iconOn: Icons.screen_rotation,
          iconOff: Icons.screen_lock_rotation,
          label: context.l10n.t('autoRotateToggle'),
          onToggle: (on) =>
              _runAdbAction(context, ref, actions.setAutoRotate(device.id, on)),
        ),
        _ActionButton(
          icon: Icons.center_focus_strong,
          label: context.l10n.t('focus'),
          onPressed: () =>
              _showAdbResult(context, ref, actions.currentFocus(device.id)),
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
              await _runAdbAction(context, ref, actions.reboot(device.id));
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
      ref,
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
        _ToggleActionButton(
          iconOn: Icons.border_outer,
          iconOff: Icons.border_clear,
          label: context.l10n.t('layoutBoundsToggle'),
          onToggle: (on) => _runAdbAction(
            context,
            ref,
            actions.toggleLayoutBounds(device.id, on),
          ),
        ),
        _ToggleActionButton(
          iconOn: Icons.dark_mode,
          iconOff: Icons.light_mode,
          label: context.l10n.t('darkLightToggle'),
          onToggle: (on) =>
              _runAdbAction(context, ref, actions.setDarkMode(device.id, on)),
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

  /// 对应用名和包名执行大小写不敏感筛选，并且支持拼音匹配（全拼、首字母），可隐藏系统应用。
  List<AdbPackage> _filterPackages(List<AdbPackage> items) {
    final filter = _filter.trim().toLowerCase();
    final cleanFilter = filter.replaceAll(' ', '');
    return items
        .where((package) => !_hideSystemApps || !package.system)
        .where((package) {
          if (filter.isEmpty) {
            return true;
          }
          final nameMatch = package.name.toLowerCase().contains(filter);
          final displayNameMatch = package.displayName.toLowerCase().contains(
            filter,
          );
          final versionMatch = package.versionLabel.toLowerCase().contains(
            filter,
          );

          if (nameMatch || displayNameMatch || versionMatch) {
            return true;
          }

          // 拼音筛选：全拼和首字母匹配（忽略空格）
          final displayNamePinyin = PinyinHelper.getPinyin(
            package.displayName,
            separator: '',
            format: PinyinFormat.WITHOUT_TONE,
          ).toLowerCase().replaceAll(' ', '');

          final displayNameShortPinyin = PinyinHelper.getShortPinyin(
            package.displayName,
          ).toLowerCase().replaceAll(' ', '');

          return displayNamePinyin.contains(cleanFilter) ||
              displayNameShortPinyin.contains(cleanFilter);
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
class _PackageTable extends StatefulWidget {
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
  State<_PackageTable> createState() => _PackageTableState();
}

class _PackageTableState extends State<_PackageTable> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _PackageTableWidths.adaptive(
          context: context,
          packages: widget.packages,
          viewportWidth: constraints.maxWidth,
        );
        final tableWidth = max(widths.total, constraints.maxWidth);

        return Scrollbar(
          controller: _horizontalController,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalController,
            primary: false,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _PackageTableHeader(widths: widths),
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalController,
                      child: ListView.builder(
                        controller: _verticalController,
                        primary: false,
                        itemCount: widget.packages.length,
                        itemBuilder: (context, index) {
                          final package = widget.packages[index];
                          return _PackageTableRow(
                            deviceId: widget.deviceId,
                            package: package,
                            selected: package.name == widget.selectedPackage,
                            widths: widths,
                            onSelected: () => widget.onSelected(package.name),
                          );
                        },
                      ),
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

class _PackageTableWidths {
  const _PackageTableWidths({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.minSdk,
    required this.targetSdk,
    required this.storage,
    required this.status,
    required this.type,
    required this.actions,
  });

  factory _PackageTableWidths.adaptive({
    required BuildContext context,
    required List<AdbPackage> packages,
    required double viewportWidth,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final headerStyle = textTheme.titleSmall;
    final bodyStyle = textTheme.bodyMedium;
    final l10n = context.l10n;

    double headerWidth(String key) =>
        _measureTableText(l10n.t(key), headerStyle);

    double contentWidth(Iterable<String> values) {
      var width = 0.0;
      for (final value in values) {
        width = max(width, _measureTableText(value, bodyStyle));
      }
      return width;
    }

    final appName = max(
      headerWidth('appName'),
      contentWidth(packages.map((package) => package.displayName)),
    ).clamp(160.0, 320.0);
    final packageName = max(
      headerWidth('packageName'),
      contentWidth(packages.map((package) => package.name)),
    ).clamp(240.0, 520.0);
    final version = max(
      headerWidth('version'),
      contentWidth(packages.map((package) => package.versionLabel)),
    ).clamp(88.0, 150.0);
    final minSdk = max(
      headerWidth('minSdkVersion'),
      contentWidth(packages.map((package) => _sdkLabel(package.minSdk))),
    ).clamp(88.0, 112.0);
    final targetSdk = max(
      headerWidth('targetMaxSdk'),
      contentWidth(packages.map(_targetMaxSdkLabel)),
    ).clamp(108.0, 136.0);
    final storage = max(
      headerWidth('storageUsed'),
      contentWidth(packages.map((package) => package.storageLabel)),
    ).clamp(104.0, 136.0);
    final status = max(
      headerWidth('status'),
      contentWidth(
        packages.map(
          (package) => package.enabled ? l10n.t('enabled') : l10n.t('disabled'),
        ),
      ),
    ).clamp(104.0, 128.0);
    final type = max(
      headerWidth('appType'),
      contentWidth(
        packages.map(
          (package) => [
            package.system ? l10n.t('systemApp') : l10n.t('userApp'),
            package.flutter ? l10n.t('flutterApp') : l10n.t('nativeApp'),
          ].join(' / '),
        ),
      ),
    ).clamp(128.0, 164.0);
    const actions = 274.0;

    final base = _PackageTableWidths(
      appName: appName + _PackageCell.horizontalPadding + 38,
      packageName: packageName + _PackageCell.horizontalPadding,
      version: version + _PackageCell.horizontalPadding,
      minSdk: minSdk + _PackageCell.horizontalPadding,
      targetSdk: targetSdk + _PackageCell.horizontalPadding,
      storage: storage + _PackageCell.horizontalPadding,
      status: status + _PackageCell.horizontalPadding,
      type: type + _PackageCell.horizontalPadding,
      actions: actions,
    );

    if (base.total > viewportWidth) {
      var overflow = base.total - viewportWidth;
      final packageShrink = min(overflow, base.packageName - 244.0);
      overflow -= packageShrink;
      final appNameShrink = min(overflow, base.appName - 222.0);
      return base.copyWith(
        appName: base.appName - appNameShrink,
        packageName: base.packageName - packageShrink,
      );
    }

    final spareWidth = viewportWidth - base.total;
    return base.copyWith(
      appName: base.appName + spareWidth * 0.4,
      packageName: base.packageName + spareWidth * 0.6,
    );
  }

  final double appName;
  final double packageName;
  final double version;
  final double minSdk;
  final double targetSdk;
  final double storage;
  final double status;
  final double type;
  final double actions;

  double get total =>
      appName +
      packageName +
      version +
      minSdk +
      targetSdk +
      storage +
      status +
      type +
      actions;

  _PackageTableWidths copyWith({double? appName, double? packageName}) {
    return _PackageTableWidths(
      appName: appName ?? this.appName,
      packageName: packageName ?? this.packageName,
      version: version,
      minSdk: minSdk,
      targetSdk: targetSdk,
      storage: storage,
      status: status,
      type: type,
      actions: actions,
    );
  }
}

double _measureTableText(String value, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
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
class _PackageTableRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: onSelected,
      onDoubleTap: () {
        onSelected();
        _showAppDetailsDialog(context, ref, deviceId, package);
      },
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
                  ? _PackageActions(deviceId: deviceId, package: package)
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

  static const horizontalPadding = 24.0;

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
  const _PackageActions({required this.deviceId, required this.package});

  final String deviceId;
  final AdbPackage package;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(appManagementServiceProvider);
    final packageName = package.name;

    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(32),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          IconButton(
            tooltip: '应用信息',
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              _showAppDetailsDialog(context, ref, deviceId, package);
            },
          ),
          IconButton(
            tooltip: context.l10n.t('launch'),
            icon: const Icon(Icons.play_arrow),
            onPressed: () => _runAdbAction(
              context,
              ref,
              service.launch(deviceId, packageName),
            ),
          ),
          IconButton(
            tooltip: context.l10n.t('forceStop'),
            icon: const Icon(Icons.stop),
            onPressed: () => _runAdbAction(
              context,
              ref,
              service.forceStop(deviceId, packageName),
            ),
          ),
          IconButton(
            tooltip: context.l10n.t('packagePath'),
            icon: const Icon(Icons.route),
            onPressed: () => _showAdbResult(
              context,
              ref,
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
                  ref,
                  service.clearData(deviceId, packageName),
                );
              }
            },
          ),
          // 冻结/解冻按钮：根据应用当前启用状态显示对应操作
          IconButton(
            tooltip: package.enabled
                ? context.l10n.t('freezeApp')
                : context.l10n.t('unfreezeApp'),
            icon: Icon(
              package.enabled ? Icons.ac_unit : Icons.local_fire_department,
            ),
            onPressed: () async {
              final confirmMsg = package.enabled
                  ? context.l10n
                        .t('freezeAppConfirm')
                        .replaceAll('{package}', packageName)
                  : context.l10n
                        .t('unfreezeAppConfirm')
                        .replaceAll('{package}', packageName);
              final confirmed = await _confirm(context, confirmMsg);
              if (confirmed && context.mounted) {
                final result = package.enabled
                    ? await service.freezeApp(deviceId, packageName)
                    : await service.unfreezeApp(deviceId, packageName);
                if (context.mounted) {
                  final successMsg = package.enabled
                      ? context.l10n
                            .t('freezeSuccess')
                            .replaceAll('{package}', packageName)
                      : context.l10n
                            .t('unfreezeSuccess')
                            .replaceAll('{package}', packageName);
                  _showSnack(
                    context,
                    result.isSuccess ? successMsg : result.message,
                    isError: !result.isSuccess,
                  );
                }
                if (result.isSuccess) {
                  await service.refreshPackages(deviceId);
                  ref.invalidate(packagesProvider(deviceId));
                }
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
                  _showSnack(
                    context,
                    result.message,
                    isError: !result.isSuccess,
                  );
                }
                if (result.isSuccess) {
                  await service.refreshPackages(deviceId);
                  ref.invalidate(packagesProvider(deviceId));
                }
              }
            },
          ),
          IconButton(
            tooltip: context.l10n.t('exportApk'),
            icon: const Icon(Icons.download),
            onPressed: () async {
              final directory = await getDirectoryPath();
              if (directory == null || !context.mounted) {
                return;
              }
              final safeLabel = package.displayName.replaceAll(
                RegExp(r'[\\/:*?"<>|]'),
                '_',
              );
              final versionStr = package.versionName != null
                  ? '_v${package.versionName}'
                  : '';
              final fileName = '$safeLabel$versionStr.apk';
              final localSavePath = '$directory/$fileName';

              _showSnack(context, context.l10n.t('exporting'));

              final result = await service.exportApk(
                deviceId,
                packageName,
                localSavePath,
                apkPath: package.apkPath,
              );

              if (context.mounted) {
                final successMsg = context.l10n
                    .t('exportSuccess')
                    .replaceAll('{path}', localSavePath);
                final failMsg = context.l10n
                    .t('exportFailed')
                    .replaceAll('{error}', result.message);
                _showSnack(
                  context,
                  result.isSuccess ? successMsg : failMsg,
                  isError: !result.isSuccess,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

/// `/` 及其子目录的远程文件浏览器。
class _FilesTab extends ConsumerWidget {
  const _FilesTab({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(fileNavigationProvider);
    final path = navState.currentPath;
    final request = RemoteDirectoryRequest(deviceId: device.id, path: path);
    final filesAsync = ref.watch(remoteFilesProvider(request));
    final filterQuery = ref.watch(fileFilterQueryProvider);

    return DropTarget(
      onDragDone: (details) => _pushFiles(context, ref, details.files, path),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Toolbar
            Row(
              children: [
                IconButton(
                  tooltip: '后退',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: navState.canGoBack
                      ? () => ref.read(fileNavigationProvider.notifier).goBack()
                      : null,
                ),
                IconButton(
                  tooltip: '前进',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: navState.canGoForward
                      ? () => ref
                            .read(fileNavigationProvider.notifier)
                            .goForward()
                      : null,
                ),
                IconButton(
                  tooltip: '向上',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: path != '/'
                      ? () => ref.read(fileNavigationProvider.notifier).goUp()
                      : null,
                ),
                IconButton(
                  tooltip: context.l10n.t('refresh'),
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    ref.invalidate(remoteFilesProvider(request));
                  },
                ),
                const SizedBox(width: 8),
                // Path bar
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: navState.isEditingPath
                        ? TextField(
                            autofocus: true,
                            controller: TextEditingController(text: path)
                              ..selection = TextSelection.fromPosition(
                                TextPosition(offset: path.length),
                              ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                            onSubmitted: (value) {
                              ref
                                  .read(fileNavigationProvider.notifier)
                                  .navigateTo(value);
                            },
                          )
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: () {
                              ref
                                  .read(fileNavigationProvider.notifier)
                                  .setEditingPath(true);
                            },
                            child: Row(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: _buildBreadcrumbs(
                                        context,
                                        ref,
                                        path,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 14),
                                  onPressed: () {
                                    ref
                                        .read(fileNavigationProvider.notifier)
                                        .setEditingPath(true);
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  splashRadius: 16,
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                // Filter search
                SizedBox(
                  width: 150,
                  height: 38,
                  child: TextField(
                    onChanged: (val) => ref
                        .read(fileFilterQueryProvider.notifier)
                        .setQuery(val),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.filter_alt_outlined,
                        size: 16,
                      ),
                      hintText: '过滤',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                // View Mode & Hidden Files toggle
                IconButton(
                  tooltip: '网格视图',
                  icon: const Icon(Icons.grid_view_outlined, size: 20),
                  isSelected: navState.isGridView,
                  selectedIcon: const Icon(Icons.grid_view, size: 20),
                  onPressed: () {
                    ref.read(fileNavigationProvider.notifier).setGridView(true);
                  },
                ),
                IconButton(
                  tooltip: '列表视图',
                  icon: const Icon(
                    Icons.format_list_bulleted_outlined,
                    size: 20,
                  ),
                  isSelected: !navState.isGridView,
                  selectedIcon: const Icon(
                    Icons.format_list_bulleted,
                    size: 20,
                  ),
                  onPressed: () {
                    ref
                        .read(fileNavigationProvider.notifier)
                        .setGridView(false);
                  },
                ),
                IconButton(
                  tooltip: navState.showHiddenFiles ? '隐藏隐藏文件' : '显示隐藏文件',
                  icon: Icon(
                    navState.showHiddenFiles
                        ? Icons.visibility
                        : Icons.visibility_off,
                    size: 20,
                  ),
                  onPressed: () {
                    ref
                        .read(fileNavigationProvider.notifier)
                        .toggleShowHiddenFiles();
                  },
                ),
                const SizedBox(width: 8),
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
            const SizedBox(height: 16),
            // Table Header (only visible in list view)
            if (!navState.isGridView) _buildTableHeader(context),
            // Files List / Grid / Table Rows
            Expanded(
              child: filesAsync.when(
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
                  // Client-side filtering
                  var filtered = items;
                  if (!navState.showHiddenFiles) {
                    filtered = filtered
                        .where((f) => !f.name.startsWith('.'))
                        .toList();
                  }
                  if (filterQuery.isNotEmpty) {
                    filtered = filtered
                        .where(
                          (f) => f.name.toLowerCase().contains(
                            filterQuery.toLowerCase(),
                          ),
                        )
                        .toList();
                  }

                  if (filtered.isEmpty) {
                    return _PanelMessage(
                      icon: Icons.folder_open,
                      title: filterQuery.isNotEmpty
                          ? '未找到匹配的文件'
                          : context.l10n.t('emptyFolder'),
                    );
                  }

                  if (navState.isGridView) {
                    return GridView.builder(
                      padding: const EdgeInsets.only(top: 8),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 110,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.8,
                          ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final file = filtered[index];
                        return _FileGridItem(
                          file: file,
                          deviceId: device.id,
                          currentPath: path,
                          onTap: () {
                            if (file.isFolder) {
                              ref
                                  .read(fileNavigationProvider.notifier)
                                  .navigateTo(_joinRemotePath(path, file.name));
                            }
                          },
                        );
                      },
                    );
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final file = filtered[index];
                      return _FileRow(
                        file: file,
                        deviceId: device.id,
                        currentPath: path,
                        onTap: () {
                          if (file.isFolder) {
                            ref
                                .read(fileNavigationProvider.notifier)
                                .navigateTo(_joinRemotePath(path, file.name));
                          }
                        },
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

  List<Widget> _buildBreadcrumbs(
    BuildContext context,
    WidgetRef ref,
    String path,
  ) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final list = <Widget>[];

    // Root segment
    list.add(
      TextButton(
        onPressed: () {
          ref.read(fileNavigationProvider.notifier).navigateTo('/');
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          '存储',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );

    var currentAccPath = '/';
    for (final segment in segments) {
      list.add(
        Text(
          ' > ',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withOpacity(0.5),
            fontSize: 12,
          ),
        ),
      );
      currentAccPath += '$segment/';
      final segmentPath = currentAccPath;
      list.add(
        TextButton(
          onPressed: () {
            ref.read(fileNavigationProvider.notifier).navigateTo(segmentPath);
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            segment,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return list;
  }

  Widget _buildTableHeader(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.4),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('名称', style: textStyle)),
          SizedBox(width: 120, child: Text('权限', style: textStyle)),
          SizedBox(width: 180, child: Text('修改日期', style: textStyle)),
          SizedBox(width: 80, child: Text('类型', style: textStyle)),
          SizedBox(
            width: 100,
            child: Text('大小', style: textStyle, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 80), // spacer for inline actions
        ],
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

/// 单个文件网格项，支持悬停高亮和显示浮动操作按钮。
class _FileGridItem extends StatefulWidget {
  const _FileGridItem({
    required this.file,
    required this.deviceId,
    required this.currentPath,
    required this.onTap,
  });

  final RemoteFile file;
  final String deviceId;
  final String currentPath;
  final VoidCallback onTap;

  @override
  State<_FileGridItem> createState() => _FileGridItemState();
}

class _FileGridItemState extends State<_FileGridItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final theme = Theme.of(context);
    final remoteFilePath = _joinRemotePath(widget.currentPath, file.name);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: _hovering
                ? theme.colorScheme.primaryContainer.withOpacity(0.08)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovering
                  ? theme.colorScheme.primary.withOpacity(0.15)
                  : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Stack(
            children: [
              // 网格项内容
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _fileIcon(file),
                      size: 40,
                      color: file.isFolder
                          ? Colors.amber
                          : file.isLink
                          ? Colors.teal
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Tooltip(
                      message: file.linkTarget != null
                          ? '${file.name} -> ${file.linkTarget}'
                          : file.name,
                      child: Text(
                        file.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: file.isFolder ? FontWeight.w500 : null,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // 悬停时在右上角显示浮动操作按钮 (如果是文件且正在悬停)
              if (_hovering && !file.isFolder)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _RemoteFileActions(
                      deviceId: widget.deviceId,
                      remotePath: remoteFilePath,
                      fileName: file.name,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个文件行，支持悬停高亮和显示操作按钮。
class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.file,
    required this.deviceId,
    required this.currentPath,
    required this.onTap,
  });

  final RemoteFile file;
  final String deviceId;
  final String currentPath;
  final VoidCallback onTap;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final theme = Theme.of(context);
    final cellStyle = theme.textTheme.bodyMedium;

    // 类型翻译
    String typeLabel = '文件';
    if (file.isFolder) {
      typeLabel = '文件夹';
    } else if (file.isLink) {
      typeLabel = '链接';
    }

    final remoteFilePath = _joinRemotePath(widget.currentPath, file.name);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _hovering
                ? theme.colorScheme.primaryContainer.withOpacity(0.08)
                : null,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // 名称
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Icon(
                      _fileIcon(file),
                      size: 20,
                      color: file.isFolder
                          ? Colors.amber
                          : file.isLink
                          ? Colors.teal
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Tooltip(
                        message: file.linkTarget != null
                            ? '${file.name} -> ${file.linkTarget}'
                            : file.name,
                        child: Text(
                          file.name,
                          style: cellStyle?.copyWith(
                            fontWeight: file.isFolder ? FontWeight.w500 : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 权限
              SizedBox(
                width: 120,
                child: Text(
                  file.permissions,
                  style: cellStyle?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              // 修改日期
              SizedBox(
                width: 180,
                child: Text(file.modifiedDate, style: cellStyle),
              ),
              // 类型
              SizedBox(width: 80, child: Text(typeLabel, style: cellStyle)),
              // 大小
              SizedBox(
                width: 100,
                child: Text(
                  file.formattedSize,
                  style: cellStyle,
                  textAlign: TextAlign.right,
                ),
              ),
              // 操作 (悬停时显示)
              SizedBox(
                width: 80,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    opacity: _hovering ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 100),
                    child: IgnorePointer(
                      ignoring: !_hovering,
                      child: _RemoteFileActions(
                        deviceId: widget.deviceId,
                        remotePath: remoteFilePath,
                        fileName: file.name,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.l10n.t('pull'),
          icon: const Icon(Icons.download, size: 18),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
          splashRadius: 16,
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
          icon: const Icon(Icons.delete_outline, size: 18),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
          splashRadius: 16,
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
            if (result.isSuccess) {
              final currentPath = ref.read(fileNavigationProvider).currentPath;
              ref.invalidate(
                remoteFilesProvider(
                  RemoteDirectoryRequest(deviceId: deviceId, path: currentPath),
                ),
              );
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

/// 带开关状态的操作按钮，点击在开/关之间切换，图标和颜色随状态变化。
class _ToggleActionButton extends StatefulWidget {
  const _ToggleActionButton({
    required this.iconOn,
    required this.iconOff,
    required this.label,
    required this.onToggle,
  });

  final IconData iconOn;
  final IconData iconOff;
  final String label;
  final ValueChanged<bool> onToggle;

  @override
  State<_ToggleActionButton> createState() => _ToggleActionButtonState();
}

class _ToggleActionButtonState extends State<_ToggleActionButton> {
  bool _isOn = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _isOn
        ? FilledButton.icon(
            icon: Icon(widget.iconOn, size: 18),
            label: Text(widget.label),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            onPressed: () {
              setState(() => _isOn = false);
              widget.onToggle(false);
            },
          )
        : OutlinedButton.icon(
            icon: Icon(widget.iconOff, size: 18),
            label: Text(widget.label),
            onPressed: () {
              setState(() => _isOn = true);
              widget.onToggle(true);
            },
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
  WidgetRef ref,
  Future<AdbResult> future,
) async {
  final result = await future;
  await _syncAdbStateAfterResult(ref, result);
  if (!context.mounted) {
    return;
  }
  _showSnack(context, result.message, isError: !result.isSuccess);
}

Future<void> _syncAdbStateAfterResult(WidgetRef ref, AdbResult result) async {
  if (!result.isDeviceDisconnected) {
    return;
  }

  await ref.read(deviceRegistryProvider.notifier).refreshDevices();

  final disconnectedDeviceId = result.disconnectedDeviceId;
  final selected = ref.read(selectedDeviceProvider);
  if (selected == null || selected.id != disconnectedDeviceId) {
    return;
  }

  for (final device in ref.read(deviceRegistryProvider)) {
    if (device.id == selected.id) {
      ref.read(selectedDeviceProvider.notifier).select(device.toAdbDevice);
      return;
    }
  }
}

/// 主动刷新 adb 设备列表，避免仅重建 StreamProvider 时 UI 无明显反馈。
Future<void> _refreshDevices(BuildContext context, WidgetRef ref) async {
  final result = await ref
      .read(deviceRegistryProvider.notifier)
      .refreshDevices();
  if (!context.mounted) {
    return;
  }
  _showSnack(
    context,
    result.isSuccess
        ? context.l10n.t('devicesRefreshed')
        : '${context.l10n.t('adbUnavailable')}: ${result.message}',
    isError: !result.isSuccess,
  );
}

/// 重启 ADB server，并在完成后刷新设备流。
Future<void> _restartAdbServer(BuildContext context, WidgetRef ref) async {
  _showSnack(context, context.l10n.t('restartingAdb'));
  final result = await ref.read(deviceRegistryProvider.notifier).restartAdb();
  if (!context.mounted) {
    return;
  }
  _showSnack(
    context,
    result.isSuccess
        ? context.l10n.t('restartAdbSuccess')
        : '${context.l10n.t('restartAdbFailed')}: ${result.message}',
    isError: !result.isSuccess,
  );
}

/// 展示 TCP/IP 连接弹窗，供左侧导航和设备列表共同复用。
Future<void> _showConnectDeviceDialog(
  BuildContext context,
  WidgetRef ref,
) async {
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
    ref,
    ref.read(deviceRegistryProvider.notifier).connectDevice(address.trim()),
  );
}

/// 执行 adb 命令，并在弹窗中展示完整输出。
Future<void> _showAdbResult(
  BuildContext context,
  WidgetRef ref,
  Future<AdbResult> future,
) async {
  final result = await future;
  await _syncAdbStateAfterResult(ref, result);
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
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) {
    return;
  }

  final media = MediaQuery.of(context);
  final accentColor = isError
      ? Theme.of(context).colorScheme.error
      : const Color(0xff00c853);
  final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
    color: const Color(0xff171a21),
    fontWeight: FontWeight.w600,
  );

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      return Positioned(
        top: media.padding.top + 16,
        left: 16,
        right: 16,
        child: IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: media.size.width - 64),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xffd7dce5)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isError ? Icons.error : Icons.check_circle,
                        color: accentColor,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Flexible(child: Text(message, style: textStyle)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  Timer(const Duration(seconds: 2), () {
    if (entry.mounted) {
      entry.remove();
    }
  });
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

void _showAppDetailsDialog(
  BuildContext context,
  WidgetRef ref,
  String deviceId,
  AdbPackage package,
) {
  showDialog(
    context: context,
    builder: (context) {
      return _AppDetailsDialog(deviceId: deviceId, package: package);
    },
  );
}

class _AppDetailsDialog extends ConsumerStatefulWidget {
  const _AppDetailsDialog({required this.deviceId, required this.package});

  final String deviceId;
  final AdbPackage package;

  @override
  ConsumerState<_AppDetailsDialog> createState() => _AppDetailsDialogState();
}

class _AppDetailsDialogState extends ConsumerState<_AppDetailsDialog> {
  late final Future<Map<String, int>> _sizesFuture;

  @override
  void initState() {
    super.initState();
    _sizesFuture = ref
        .read(appManagementServiceProvider)
        .getPackageSizeDetails(widget.deviceId, widget.package.name);
  }

  @override
  Widget build(BuildContext context) {
    final package = widget.package;
    final theme = Theme.of(context);

    String formatEpoch(int? epochMs) {
      if (epochMs == null || epochMs <= 0) return '-';
      final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
      String pad(int value) => value.toString().padLeft(2, '0');
      return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
    }

    String formatSize(int? bytes) {
      if (bytes == null || bytes <= 0) return '-';
      const kb = 1024;
      const mb = kb * 1024;
      const gb = mb * 1024;
      if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)}G';
      if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)}M';
      if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)}K';
      return '${bytes}B';
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 440,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '应用信息',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child:
                        package.iconLocalPath != null &&
                            File(package.iconLocalPath!).existsSync()
                        ? Image.file(
                            File(package.iconLocalPath!),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                _FallbackIconLarge(
                                  package: package,
                                  theme: theme,
                                ),
                          )
                        : _FallbackIconLarge(package: package, theme: theme),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        package.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        package.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        package.versionLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _DetailItem(label: '系统应用', value: package.system ? '是' : '否'),
            _DetailItem(label: '最小 SDK 版本', value: _sdkLabel(package.minSdk)),
            _DetailItem(
              label: '目标 SDK 版本',
              value: _sdkLabel(package.targetSdk),
            ),
            _DetailItem(
              label: '首次安装时间',
              value: formatEpoch(package.firstInstallTime),
            ),
            _DetailItem(
              label: '最后更新时间',
              value: formatEpoch(package.lastUpdateTime),
            ),
            _DetailItem(
              label: '安装包大小',
              value: formatSize(package.storageBytes),
            ),
            FutureBuilder<Map<String, int>>(
              future: _sizesFuture,
              builder: (context, snapshot) {
                final sizes = snapshot.data;
                final isLoading =
                    snapshot.connectionState == ConnectionState.waiting;

                String getValue(String key) {
                  if (isLoading) return '加载中...';
                  if (snapshot.hasError || sizes == null) return '-';
                  return formatSize(sizes[key]);
                }

                return Column(
                  children: [
                    _DetailItem(label: '应用大小', value: getValue('appSize')),
                    _DetailItem(label: '数据大小', value: getValue('dataSize')),
                    _DetailItem(label: '缓存大小', value: getValue('cacheSize')),
                  ],
                );
              },
            ),
            _DetailItem(
              label: '签名 MD5',
              value: package.signatureMd5 ?? '-',
              trailing:
                  package.signatureMd5 != null &&
                      package.signatureMd5!.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: package.signatureMd5!),
                        );
                        _showSnack(context, '签名已复制到剪贴板');
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 16,
                      tooltip: '复制签名',
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackIconLarge extends StatelessWidget {
  const _FallbackIconLarge({required this.package, required this.theme});

  final AdbPackage package;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    final icon = package.flutter
        ? Icons.flutter_dash
        : package.system
        ? Icons.settings_applications
        : Icons.android;

    return Container(
      color: package.system
          ? colorScheme.surfaceContainerHighest
          : colorScheme.primaryContainer,
      child: Icon(
        icon,
        size: 40,
        color: package.system
            ? colorScheme.onSurfaceVariant
            : colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                flex: 0,
                child: Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ],
          ),
        ],
      ),
    );
  }
}

class _DevicePairingDialog extends ConsumerStatefulWidget {
  const _DevicePairingDialog();

  @override
  ConsumerState<_DevicePairingDialog> createState() =>
      _DevicePairingDialogState();
}

class _DevicePairingDialogState extends ConsumerState<_DevicePairingDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _ssid;
  late String _password;
  Timer? _pairingTimer;
  bool _isPairing = false;
  String _statusMessage = '';
  bool _isError = false;

  final _addressController = TextEditingController(text: '192.168.1.10:37123');
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _generateQrCredentials();
    _startMdnsDiscovery();
  }

  @override
  void dispose() {
    _pairingTimer?.cancel();
    _tabController.dispose();
    _addressController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _generateQrCredentials() {
    final rand = Random();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final randomString = List.generate(
      6,
      (index) => chars[rand.nextInt(chars.length)],
    ).join();
    _ssid = 'adb-manage-$randomString';

    const digits = '0123456789';
    _password = List.generate(
      6,
      (index) => digits[rand.nextInt(digits.length)],
    ).join();
  }

  void _startMdnsDiscovery() {
    _pairingTimer?.cancel();
    _pairingTimer = Timer.periodic(const Duration(milliseconds: 1500), (
      timer,
    ) async {
      if (_isPairing) return;
      final adb = ref.read(adbServiceProvider);
      final result = await adb.run(['mdns', 'services']);
      if (!mounted) return;

      if (result.isSuccess) {
        final lines = result.stdout.split('\n');
        for (final line in lines) {
          if (line.contains('_adb-tls-pairing._tcp') && line.contains(_ssid)) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 3) {
              final pairingAddress = parts[2].trim();
              timer.cancel();
              _performPairAndConnect(pairingAddress, _password);
              break;
            }
          }
        }
      }
    });
  }

  Future<void> _performPairAndConnect(String address, String code) async {
    setState(() {
      _isPairing = true;
      _statusMessage = context.l10n.t('pairing');
      _isError = false;
    });

    final result = await ref
        .read(deviceRegistryProvider.notifier)
        .pairAndConnect(address, code);
    if (!mounted) return;

    setState(() {
      _isPairing = false;
      if (result.isSuccess) {
        _statusMessage = context.l10n.t('pairSuccess');
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      } else {
        _statusMessage = '${context.l10n.t('pairFailed')}: ${result.message}';
        _isError = true;
        // Resume QR code discovery if we were on the QR tab
        if (_tabController.index == 0) {
          _startMdnsDiscovery();
        }
      }
    });
  }

  Future<void> _manualPair() async {
    final address = _addressController.text.trim();
    final code = _codeController.text.trim();
    if (address.isEmpty || code.isEmpty) {
      return;
    }
    _pairingTimer?.cancel();
    await _performPairAndConnect(address, code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(context.l10n.t('pairDeviceTitle')),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: context.l10n.t('pairQr')),
                Tab(text: context.l10n.t('pairCode')),
              ],
              onTap: (index) {
                if (index == 0) {
                  _startMdnsDiscovery();
                } else {
                  _pairingTimer?.cancel();
                }
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Tab 1: QR Code
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: 'WIFI:T:ADB;S:$_ssid;P:$_password;;',
                          version: QrVersions.auto,
                          size: 180,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.t('qrInstruction'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${context.l10n.t('pairingCode')}: $_password',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  // Tab 2: Pairing Code
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.t('codeInstruction'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _addressController,
                          decoration: InputDecoration(
                            labelText:
                                '${context.l10n.t('ipAddress')} & ${context.l10n.t('pairingPort')}',
                            hintText: '192.168.1.10:37123',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.link),
                          ),
                          keyboardType: TextInputType.text,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _codeController,
                          decoration: InputDecoration(
                            labelText: context.l10n.t('pairingCode'),
                            hintText: '123456',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.pin),
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isPairing ? null : _manualPair,
                          icon: const Icon(Icons.vpn_key),
                          label: Text(context.l10n.t('connect')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Common Status indicator
            if (_isPairing || _statusMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isPairing) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      _statusMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _isError
                            ? theme.colorScheme.error
                            : _statusMessage == context.l10n.t('pairSuccess')
                            ? Colors.green
                            : theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
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
