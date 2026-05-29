part of '../dashboard_screen.dart';

class _AppPermissionsDialog extends ConsumerStatefulWidget {
  const _AppPermissionsDialog({required this.deviceId, required this.package});

  final String deviceId;
  final AdbPackage package;

  @override
  ConsumerState<_AppPermissionsDialog> createState() => _AppPermissionsDialogState();
}

class _AppPermissionsDialogState extends ConsumerState<_AppPermissionsDialog> {
  bool _loading = true;
  String? _error;
  List<AdbAppPermission> _permissions = [];
  List<AdbAppPermission> _filteredPermissions = [];
  String _searchQuery = '';
  bool _onlyRuntime = true;
  final Set<String> _togglingPermissions = {};

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final perms = await ref.read(appPermissionServiceProvider).getPermissions(
        widget.deviceId,
        widget.package.name,
      );
      if (mounted) {
        setState(() {
          _permissions = perms;
          _filterPermissions();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _filterPermissions() {
    final query = _searchQuery.trim().toLowerCase();
    var list = _permissions;
    if (_onlyRuntime) {
      list = list.where((p) => p.isRuntime).toList();
    }
    if (query.isNotEmpty) {
      list = list.where((p) => p.name.toLowerCase().contains(query)).toList();
    }
    _filteredPermissions = list;
  }

  Future<void> _togglePermission(AdbAppPermission permission, bool targetValue) async {
    final name = permission.name;
    setState(() {
      _togglingPermissions.add(name);
    });

    try {
      final service = ref.read(appPermissionServiceProvider);
      final result = targetValue
          ? await service.grantPermission(widget.deviceId, widget.package.name, name)
          : await service.revokePermission(widget.deviceId, widget.package.name, name);

      if (!mounted) return;

      if (result.isSuccess) {
        final actionMsg = targetValue
            ? context.l10n.t('grantSuccess').replaceAll('{permission}', _getShortName(name))
            : context.l10n.t('revokeSuccess').replaceAll('{permission}', _getShortName(name));
        _showSnack(context, actionMsg);
        
        setState(() {
          final idx = _permissions.indexWhere((p) => p.name == name);
          if (idx != -1) {
            _permissions[idx] = AdbAppPermission(
              name: name,
              granted: targetValue,
              isRuntime: permission.isRuntime,
            );
            _filterPermissions();
          }
        });
      } else {
        final failMsg = targetValue
            ? context.l10n.t('grantFailed').replaceAll('{error}', result.message)
            : context.l10n.t('revokeFailed').replaceAll('{error}', result.message);
        _showSnack(context, failMsg, isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnack(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _togglingPermissions.remove(name);
        });
      }
    }
  }

  String _getShortName(String name) {
    final idx = name.lastIndexOf('.');
    return idx != -1 ? name.substring(idx + 1) : name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final package = widget.package;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 540,
        constraints: const BoxConstraints(maxHeight: 640),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部标题与关闭按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10n.t('permissions'),
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
            const SizedBox(height: 16),
            
            // 应用基本信息展示
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: package.iconLocalPath != null &&
                            File(package.iconLocalPath!).existsSync()
                        ? Image.file(
                            File(package.iconLocalPath!),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                _FallbackIconLarge(package: package, theme: theme),
                          )
                        : _FallbackIconLarge(package: package, theme: theme),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        package.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        package.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // 搜索过滤与只看运行时开关
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: context.l10n.t('searchPermission'),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _filterPermissions();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _onlyRuntime,
                      onChanged: (value) {
                        setState(() {
                          _onlyRuntime = value ?? true;
                          _filterPermissions();
                        });
                      },
                    ),
                    Text(
                      context.l10n.t('onlyRuntimePermissions'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 权限列表区域
            Expanded(
              child: _buildContent(context, theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(context.l10n.t('loadingPermissions')),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              context.l10n.t('permissionsLoadFailed').replaceAll('{error}', _error!),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.t('refresh')),
              onPressed: _loadPermissions,
            ),
          ],
        ),
      );
    }

    if (_filteredPermissions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.rule_folder_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.t('noPermissions'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredPermissions.length,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemBuilder: (context, index) {
        final perm = _filteredPermissions[index];
        final shortName = _getShortName(perm.name);
        final isToggling = _togglingPermissions.contains(perm.name);
        
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Icon(
              perm.isRuntime ? Icons.security_rounded : Icons.info_outline_rounded,
              color: perm.granted 
                  ? theme.colorScheme.primary 
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              size: 22,
            ),
            title: Text(
              shortName,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              perm.name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
            trailing: perm.isRuntime
                ? (isToggling
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Switch(
                        value: perm.granted,
                        onChanged: (value) => _togglePermission(perm, value),
                      ))
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: perm.granted 
                          ? theme.colorScheme.primaryContainer 
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      perm.granted 
                          ? context.l10n.t('permissionGranted') 
                          : context.l10n.t('permissionDenied'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: perm.granted
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

void _showAppPermissionsDialog(
  BuildContext context,
  WidgetRef ref,
  String deviceId,
  AdbPackage package,
) {
  showDialog(
    context: context,
    builder: (context) {
      return _AppPermissionsDialog(deviceId: deviceId, package: package);
    },
  );
}
