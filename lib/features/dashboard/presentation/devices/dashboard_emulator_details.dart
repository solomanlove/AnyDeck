part of '../dashboard_screen.dart';

class _EmulatorDetailsPanel extends ConsumerWidget {
  const _EmulatorDetailsPanel({
    required this.item,
    required this.onClose,
  });

  final _EmulatorItem item;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final emulator = item.emulator;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF09C47C).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    CupertinoIcons.device_desktop,
                    color: Color(0xFF09C47C),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.t('emulatorDetails'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        emulator.displayName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark, size: 18),
                  onPressed: onClose,
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status & Basic Info
                  _buildStatusCard(context),
                  const SizedBox(height: 16),
                  
                  // Key Configuration Cards
                  _buildSectionTitle(context, '基本属性'),
                  const SizedBox(height: 8),
                  _buildDetailTile(
                    context, 
                    icon: CupertinoIcons.info_circle,
                    label: context.l10n.t('emulatorNameCol'), 
                    value: emulator.name,
                    copyable: true,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailTile(
                    context,
                    icon: CupertinoIcons.folder,
                    label: context.l10n.t('avdPath'),
                    value: emulator.avdDirectory?.path ?? '-',
                    copyable: true,
                    action: emulator.avdDirectory != null ? IconButton(
                      icon: const Icon(CupertinoIcons.folder_open, size: 16),
                      tooltip: context.l10n.t('openAvdFolder'),
                      onPressed: () => ref.read(emulatorServiceProvider).openAvdDirectory(emulator),
                      style: IconButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(28, 28),
                      ),
                    ) : null,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailTile(
                    context,
                    icon: CupertinoIcons.fullscreen,
                    label: context.l10n.t('emulatorResolutionCol'),
                    value: emulator.resolutionLabel,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailTile(
                    context,
                    icon: CupertinoIcons.number,
                    label: context.l10n.t('emulatorSdkCol'),
                    value: emulator.sdkVersionLabel,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailTile(
                    context,
                    icon: Icons.memory,
                    label: context.l10n.t('emulatorAbiCol'),
                    value: emulator.abiLabel,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailTile(
                    context,
                    icon: CupertinoIcons.square_grid_2x2,
                    label: context.l10n.t('emulatorMemoryCol'),
                    value: emulator.memoryLabel,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailTile(
                    context,
                    icon: CupertinoIcons.device_laptop,
                    label: context.l10n.t('emulatorStorageCol'),
                    value: emulator.storageLabel,
                  ),
                  const SizedBox(height: 20),
                  
                  // View All Configurations Button
                  FilledButton.icon(
                    onPressed: () => _showAllConfigDialog(context),
                    icon: const Icon(CupertinoIcons.list_bullet, size: 16),
                    label: Text(context.l10n.t('viewAllConfig')),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = switch (item.status) {
      'running' => (const Color(0xFF2E7D32), context.l10n.t('emulatorRunning')),
      'starting' => (const Color(0xFFE65100), context.l10n.t('emulatorStarting')),
      _ => (const Color(0xFF9E9E9E), context.l10n.t('emulatorStopped')),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildDetailTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool copyable = false,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (copyable && value != '-') ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
              tooltip: '复制',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                _showToast(context, context.l10n.t('copiedToClipboard').replaceAll('{label}', label));
              },
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(28, 28),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAllConfigDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _EmulatorFullConfigDialog(
        emulatorName: item.emulator.displayName,
        config: item.emulator.config,
      ),
    );
  }

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _EmulatorFullConfigDialog extends StatefulWidget {
  const _EmulatorFullConfigDialog({
    required this.emulatorName,
    required this.config,
  });

  final String emulatorName;
  final Map<String, String> config;

  @override
  State<_EmulatorFullConfigDialog> createState() => _EmulatorFullConfigDialogState();
}

class _EmulatorFullConfigDialogState extends State<_EmulatorFullConfigDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Filter configurations based on query
    final query = _searchQuery.trim().toLowerCase();
    final entries = widget.config.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.key.toLowerCase().contains(query) ||
          entry.value.toLowerCase().contains(query);
    }).toList();

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.t('emulatorDetails'),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.emulatorName,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.xmark),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        height: 480,
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(CupertinoIcons.search),
                  hintText: context.l10n.t('searchConfig'),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(CupertinoIcons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            const Divider(height: 1),
            // Header Row
            Container(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      context.l10n.t('configKey'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Text(
                      context.l10n.t('configValue'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Configuration List
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(CupertinoIcons.search, size: 48, color: colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            context.l10n.t('noConfigMatches'),
                            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      itemCount: entries.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _EmulatorConfigRow(
                          configKey: entry.key,
                          configValue: entry.value,
                        );
                      },
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

class _EmulatorConfigRow extends StatelessWidget {
  const _EmulatorConfigRow({
    required this.configKey,
    required this.configValue,
  });

  final String configKey;
  final String configValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              configKey,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    configValue,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                  tooltip: context.l10n.t('copyConfig'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '$configKey=$configValue'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.t('copiedToClipboard').replaceAll('{label}', configKey)),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(24, 24),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
