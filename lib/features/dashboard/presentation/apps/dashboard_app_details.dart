part of '../dashboard_screen.dart';

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
        constraints: const BoxConstraints(maxHeight: 560),
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
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                              icon: const Icon(CupertinoIcons.doc_on_doc, size: 16),
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
        ? CupertinoIcons.square_grid_2x2
        : package.system
        ? CupertinoIcons.settings
        : CupertinoIcons.device_phone_portrait;

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
