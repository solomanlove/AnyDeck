part of '../dashboard_screen.dart';

/// 权限弹窗只负责容器与应用信息，操作界面与详情页共享。
class _AppPermissionsDialog extends StatelessWidget {
  const _AppPermissionsDialog({required this.deviceId, required this.package});
  final String deviceId;
  final AdbPackage package;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                  icon: const Icon(CupertinoIcons.xmark),
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

            Expanded(
              child: AppPermissionsPanel(
                deviceId: deviceId,
                packageName: package.name,
              ),
            ),
          ],
        ),
      ),
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
