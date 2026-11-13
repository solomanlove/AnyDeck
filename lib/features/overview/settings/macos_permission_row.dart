import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/permissions/mac_permission.dart';

/// 权限用途、实时状态和单项操作行，供 macOS 权限设置复用。
///
/// permission 决定用途文案，status 必须来自系统读取结果；loading 仅用于
/// 首次读取，busy 禁止重复操作，onAction 由页面选择申请授权或打开系统设置。
/// 在设置页的 Column 中使用，不创建独立滚动区域。
class MacPermissionRow extends StatelessWidget {
  const MacPermissionRow({
    super.key,
    required this.permission,
    required this.status,
    required this.loading,
    required this.busy,
    required this.onAction,
  });

  final MacPermission permission;
  final MacPermissionStatus status;
  final bool loading;
  final bool busy;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unavailable =
        status == MacPermissionStatus.unsupported ||
        status == MacPermissionStatus.notRequired;
    final request =
        permission.supportsRequest &&
        status == MacPermissionStatus.notDetermined;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.t(permission.titleKey),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.t(permission.descriptionKey),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.t(loading ? 'macPermissionsLoading' : status.labelKey),
          key: ValueKey('mac-permission-status-${permission.name}'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: status == MacPermissionStatus.authorized
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    final action = OutlinedButton(
      key: ValueKey('mac-permission-action-${permission.name}'),
      onPressed: busy || unavailable ? null : onAction,
      child: Text(
        context.l10n.t(
          request ? 'macPermissionsRequest' : 'macPermissionsOpenSettings',
        ),
      ),
    );
    return Padding(
      key: ValueKey('mac-permission-${permission.name}'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 540
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: 12), action],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: action,
                  ),
                ],
              ),
      ),
    );
  }
}
