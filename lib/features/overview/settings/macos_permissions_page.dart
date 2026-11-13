import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/permissions/mac_permission.dart';
import '../../../core/permissions/mac_permissions_controller.dart';
import 'macos_permission_row.dart';

/// macOS 权限管理内容，嵌入 SettingsWorkspace 的滚动区域。
///
/// 挂载时仅读取状态；用户点击单项操作后才请求授权。返回前台时刷新，
/// 无后台轮询或设置持久化，关闭分类后会释放窗口及应用生命周期监听。
class MacPermissionsPanel extends ConsumerStatefulWidget {
  const MacPermissionsPanel({super.key});

  @override
  ConsumerState<MacPermissionsPanel> createState() =>
      _MacPermissionsPanelState();
}

class _MacPermissionsPanelState extends ConsumerState<MacPermissionsPanel>
    with WidgetsBindingObserver, WindowListener {
  bool _hasRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void onWindowFocus() => _refresh();

  void _refresh() {
    if (!mounted) return;
    final state = ref.read(macPermissionsProvider);
    if (state.busy != null || (state.loading && _hasRequested)) return;
    _hasRequested = true;
    ref.read(macPermissionsProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(macPermissionsProvider);
    final busy = state.loading || state.busy != null;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.t('macPermissionsDescription'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('mac-permissions-refresh'),
              onPressed: busy ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(context.l10n.t('macPermissionsRefresh')),
            ),
          ),
          if (state.loading) const LinearProgressIndicator(),
          if (state.errorKey != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.l10n.t(state.errorKey!),
                key: const ValueKey('mac-permissions-error'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          for (final permission in MacPermission.values) ...[
            if (permission != MacPermission.values.first)
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
            MacPermissionRow(
              permission: permission,
              status: state.statusFor(permission),
              loading: state.loading && state.statuses.isEmpty,
              busy: busy,
              onAction: () {
                final notifier = ref.read(macPermissionsProvider.notifier);
                if (permission.supportsRequest &&
                    state.statusFor(permission) ==
                        MacPermissionStatus.notDetermined) {
                  notifier.request(permission);
                } else {
                  notifier.openSettings(permission);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
