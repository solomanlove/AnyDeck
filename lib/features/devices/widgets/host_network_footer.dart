import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widget/app_toast.dart';
import '../../../app/window/widget/desktop_workspace_surface.dart';
import '../../../core/network/host_network_info.dart';
import '../../../core/providers/host_network_provider.dart';
import '../../console/controller/console_dock_controller.dart';
import '../../diagnostics/widgets/services_diagnostics_button.dart';

/// 全局底部状态栏：左侧本机 IP 与网络详情，右侧统一服务诊断入口。
///
/// 只订阅已有网络快照；刷新和权限读取均由用户在详情内主动触发。
/// 放在 ConsoleDock 外侧，设备视图切换及控制台展开时位置保持不变。
class HostNetworkFooter extends ConsumerWidget {
  const HostNetworkFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(hostNetworkProvider);
    final info = network.asData?.value;
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurfaceVariant;
    final address = info?.address?.ipv4;
    final placeholder = context.l10n.t(
      network.isLoading ? 'hostNetworkLoading' : 'deviceWorkspaceMissingIp',
    );
    final footer = Container(
      key: const Key('hostNetworkFooter'),
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: DefaultTextStyle(
        style: theme.textTheme.bodySmall!.copyWith(
          fontSize: 11,
          color: foreground,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final host = Wrap(
              spacing: 5,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.laptop_mac_outlined, size: 14),
                if (constraints.maxWidth > 420)
                  Text('${context.l10n.t('deviceWorkspaceHostIp')}：'),
                _selectableNetworkValue(
                  Text(
                    address ?? placeholder,
                    key: const Key('hostNetworkAddress'),
                    style: TextStyle(fontSize: 11, color: foreground),
                  ),
                ),
                IconButton(
                  key: const Key('copyHostIp'),
                  tooltip: context.l10n.t('deviceWorkspaceCopyIp'),
                  onPressed: address == null
                      ? null
                      : () async {
                          try {
                            await Clipboard.setData(
                              ClipboardData(text: address),
                            );
                            if (context.mounted) {
                              AppToast.show(
                                context,
                                context.l10n.t('copySuccess'),
                              );
                            }
                          } catch (error) {
                            if (context.mounted) {
                              AppToast.show(
                                context,
                                '${context.l10n.t('error')}: $error',
                                isError: true,
                              );
                            }
                          }
                        },
                  style: _statusIconStyle(foreground),
                  icon: const Icon(Icons.copy_outlined, size: 13),
                ),
                MenuAnchor(
                  style: MenuStyle(
                    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                    backgroundColor: WidgetStatePropertyAll(
                      theme.colorScheme.surface,
                    ),
                    shape: const WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: AppThemeSizes.radiusLarge,
                      ),
                    ),
                  ),
                  menuChildren: [
                    SizedBox(
                      width: constraints.maxWidth.clamp(180, 300),
                      child: const _HostNetworkDetails(),
                    ),
                  ],
                  builder: (context, controller, _) => TextButton(
                    key: const Key('hostNetworkDetails'),
                    style: TextButton.styleFrom(
                      foregroundColor: foreground,
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      textStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            context.l10n.t('deviceWorkspaceNetworkDetails'),
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(Icons.keyboard_arrow_up, size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            );
            final diagnostics = ServicesDiagnosticsButton(
              foregroundColor: foreground,
            );
            if (constraints.maxWidth <
                440 * MediaQuery.textScalerOf(context).scale(1)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  host,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: context.l10n.t('console'),
                        style: _statusIconStyle(foreground),
                        onPressed: ref
                            .read(consoleDockProvider.notifier)
                            .toggle,
                        icon: const Icon(Icons.article_outlined, size: 14),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: diagnostics,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: host),
                const SizedBox(width: 8),
                diagnostics,
              ],
            );
          },
        ),
      ),
    );
    // 所有右侧页面底栏与一级标题栏共用背景材质，避免主色染色。
    return DesktopWorkspaceSurface(
      child: IconTheme.merge(
        data: IconThemeData(color: foreground),
        child: footer,
      ),
    );
  }

  ButtonStyle _statusIconStyle(Color foreground) => IconButton.styleFrom(
    foregroundColor: foreground,
    minimumSize: const Size(24, 28),
    maximumSize: const Size(28, 28),
    padding: EdgeInsets.zero,
    iconSize: 14,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

/// 动态网络值使用普通文本语义，避免 macOS 将更新当作开始编辑。
/// 文字仍支持鼠标拖选和快捷键复制，Tab 导航直接移到操作按钮。
Widget _selectableNetworkValue(Text text) =>
    ExcludeFocusTraversal(child: SelectionArea(child: text));

/// 详情弹层使用同一个网络 Provider，保留权限状态、实际网卡与手动刷新。
class _HostNetworkDetails extends ConsumerWidget {
  const _HostNetworkDetails();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(hostNetworkProvider);
    final info = network.value;
    final l10n = context.l10n;
    final placeholder = l10n.t(
      network.isLoading ? 'hostNetworkLoading' : 'hostNetworkUnavailable',
    );
    final wifi =
        info?.ssid ??
        l10n.t(switch (info?.wifiStatus) {
          HostWifiStatus.disconnected => 'hostWifiDisconnected',
          HostWifiStatus.permissionRequired => 'hostWifiPermissionRequired',
          _ => 'hostNetworkUnavailable',
        });
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('hostNetworkComputer'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          for (final item in [
            (
              l10n.t('deviceWorkspaceHostIp'),
              info?.address?.ipv4 ?? placeholder,
            ),
            ('Wi-Fi', wifi),
            (
              l10n.t('deviceWorkspaceInterface'),
              info?.address?.interfaceName ?? placeholder,
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(item.$1, style: const TextStyle(fontSize: 12)),
                  ),
                  Flexible(
                    child: _selectableNetworkValue(
                      Text(
                        item.$2,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (network.hasError)
            Text(
              '${l10n.t('error')}: ${network.error}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          if (info?.wifiStatus == HostWifiStatus.permissionRequired)
            TextButton(
              onPressed: network.isLoading
                  ? null
                  : () => ref
                        .read(hostNetworkProvider.notifier)
                        .refresh(requestWifiAccess: true),
              child: Text(l10n.t('hostWifiReadName')),
            ),
          const Divider(),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: network.isLoading
                  ? null
                  : () => ref.read(hostNetworkProvider.notifier).refresh(),
              icon: network.isLoading
                  ? const SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  : const Icon(Icons.refresh, size: 14),
              label: Text(
                l10n.t('hostNetworkRefresh'),
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
