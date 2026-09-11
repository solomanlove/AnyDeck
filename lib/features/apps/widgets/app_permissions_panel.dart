import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/apps/adb_app_permission.dart';
import '../../../core/apps/app_permission_controller.dart';

/// 详情页和权限弹窗复用分类、搜索与批量操作界面。
class AppPermissionsPanel extends ConsumerWidget {
  const AppPermissionsPanel({
    super.key,
    required this.deviceId,
    required this.packageName,
  });
  final String deviceId;
  final String packageName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = appPermissionControllerProvider((deviceId, packageName));
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final blocked = state.busy || state.loading || state.error != null;
    final query = state.query.trim().toLowerCase();
    final filtered = state.permissions
        .where(
          (p) =>
              p.name.toLowerCase().contains(query) && _matches(p, state.filter),
        )
        .toList();
    final hasGranted = state.permissions.any((p) => p.isRuntime && p.granted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: state.query,
          onChanged: controller.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: l10n.t('searchPermission'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final filter in AppPermissionFilter.values)
              ChoiceChip(
                label: Text(
                  '${l10n.t(_filterKey(filter))} (${state.permissions.where((p) => _matches(p, filter)).length})',
                ),
                selected: state.filter == filter,
                onSelected: (_) => controller.filter(filter),
              ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.remove_moderator_outlined, size: 18),
              label: Text(
                l10n.t(
                  state.busy ? 'permissionUpdating' : 'revokeAllPermissions',
                ),
              ),
              onPressed: blocked || !hasGranted
                  ? null
                  : () async {
                      final result = await controller.revokeAll(
                        () async =>
                            await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: Text(l10n.t('revokeAllPermissions')),
                                content: Text(
                                  l10n
                                      .t('revokeAllPermissionsConfirm')
                                      .replaceAll('{package}', packageName),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: Text(l10n.t('cancel')),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: Text(l10n.t('confirm')),
                                  ),
                                ],
                              ),
                            ) ??
                            false,
                      );
                      if (!context.mounted || result == null) return;
                      final summary = result.total == 0
                          ? l10n.t('revokeAllPermissionsNone')
                          : l10n
                                .t('revokeAllPermissionsSuccess')
                                .replaceAll('{count}', '${result.succeeded}');
                      if (result.failedPermissions.isEmpty) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(summary)));
                      } else {
                        await showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(
                              l10n
                                  .t('failedRevokeCount')
                                  .replaceAll(
                                    '{count}',
                                    '${result.failedPermissions.length}',
                                  )
                                  .replaceAll('{total}', '${result.total}'),
                            ),
                            content: SingleChildScrollView(
                              child: SelectableText(
                                '$summary\n\n${result.failedPermissions.map((name) => '$name\n${result.errors[name] ?? l10n.t('permissionStillGranted')}').join('\n\n')}',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(l10n.t('close')),
                              ),
                            ],
                          ),
                        );
                      }
                    },
            ),
            IconButton(
              tooltip: l10n.t('refresh'),
              onPressed: state.busy || state.loading
                  ? null
                  : controller.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            l10n.t('permissionScopeHint'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        if (state.busy) const LinearProgressIndicator(),
        Expanded(
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.error != null
              ? Center(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      l10n
                          .t('permissionsLoadFailed')
                          .replaceAll('{error}', state.error!),
                    ),
                  ),
                )
              : filtered.isEmpty
              ? Center(child: Text(l10n.t('noPermissions')))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final permission = filtered[index];
                    final type = !permission.isKnownType
                        ? 'unknownPermissionType'
                        : permission.isRuntime
                        ? 'dynamicPermission'
                        : 'staticPermission';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      title: Text(
                        permission.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '${l10n.t(type)} · ${l10n.t(permission.granted ? 'permissionGranted' : 'permissionDenied')}${permission.isFixed ? ' · ${l10n.t('permissionFixed')}' : ''}',
                        style: TextStyle(
                          color: permission.granted
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      trailing: permission.canChange
                          ? Switch(
                              value: permission.granted,
                              onChanged: blocked
                                  ? null
                                  : (value) async {
                                      final error = await controller.toggle(
                                        permission,
                                        value,
                                      );
                                      if (context.mounted && error != null) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              l10n
                                                  .t(
                                                    value
                                                        ? 'grantFailed'
                                                        : 'revokeFailed',
                                                  )
                                                  .replaceAll('{error}', error),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                            )
                          : Tooltip(
                              message: l10n.t(
                                permission.isFixed
                                    ? 'permissionFixed'
                                    : 'permissionReadOnly',
                              ),
                              child: Icon(
                                Icons.lock_outline,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static bool _matches(AdbAppPermission p, AppPermissionFilter filter) =>
      switch (filter) {
        AppPermissionFilter.all => true,
        AppPermissionFilter.runtime => p.isRuntime,
        AppPermissionFilter.install => p.isKnownType && !p.isRuntime,
        AppPermissionFilter.unknown => !p.isKnownType,
      };

  static String _filterKey(AppPermissionFilter filter) => switch (filter) {
    AppPermissionFilter.all => 'allPermissions',
    AppPermissionFilter.runtime => 'dynamicPermission',
    AppPermissionFilter.install => 'staticPermission',
    AppPermissionFilter.unknown => 'unknownPermissionType',
  };
}
