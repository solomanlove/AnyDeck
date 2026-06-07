part of '../dashboard_screen.dart';

class _WifiPasswordsDialog extends ConsumerStatefulWidget {
  const _WifiPasswordsDialog({required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<_WifiPasswordsDialog> createState() =>
      _WifiPasswordsDialogState();
}

class _WifiPasswordsDialogState extends ConsumerState<_WifiPasswordsDialog> {
  bool _isLoading = true;
  List<WifiCredentials> _allCredentials = [];
  List<WifiCredentials> _filteredCredentials = [];
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _visiblePasswordIndices = {};

  @override
  void initState() {
    super.initState();
    _loadWifiCredentials();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWifiCredentials() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final adb = ref.read(adbServiceProvider);
      // Ensure the device runs as root first if possible, or check if already rooted
      final isRoot = await ref.read(
        isDeviceRootProvider(widget.deviceId).future,
      );
      if (isRoot) {
        final creds = await WifiCredentialsHelper.fetchSavedWifi(
          adb,
          widget.deviceId,
        );
        if (mounted) {
          setState(() {
            _allCredentials = creds;
            _filteredCredentials = creds;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _allCredentials = [];
          _filteredCredentials = [];
          _isLoading = false;
        });
      }
    }
  }

  void _filterSSID(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCredentials = _allCredentials;
      } else {
        _filteredCredentials = _allCredentials
            .where((c) => c.ssid.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRootAsync = ref.watch(isDeviceRootProvider(widget.deviceId));
    final isRoot = isRootAsync.value ?? false;

    Widget content;

    if (isRootAsync.isLoading || _isLoading) {
      content = SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(context.l10n.t('loadingWifiPasswords')),
            ],
          ),
        ),
      );
    } else if (!isRoot) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.shield_slash,
              color: Colors.orange,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.t('wifiPasswordNoRoot'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                context.l10n.t('wifiPasswordNoRootDetail'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    } else if (_allCredentials.isEmpty) {
      content = SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.wifi_slash,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(context.l10n.t('wifiPasswordEmpty')),
            ],
          ),
        ),
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: context.l10n.t('wifiPasswordSearchHint'),
              prefixIcon: const Icon(CupertinoIcons.search),
              isDense: true,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
            onChanged: _filterSSID,
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 350),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _filteredCredentials.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final cred = _filteredCredentials[index];
                final isPasswordVisible = _visiblePasswordIndices.contains(
                  index,
                );

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          cred.ssid,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.doc_on_doc, size: 16),
                        tooltip: '复制 SSID',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: cred.ssid));
                          _showSnack(
                            context,
                            context.l10n.t('wifiPasswordCopySsidSuccess'),
                          );
                        },
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${context.l10n.t('wifiPasswordSecurity')}: ${cred.securityType}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('${context.l10n.t('wifiPasswordKey')}: '),
                          Expanded(
                            child: Text(
                              cred.password.isEmpty
                                  ? '无密码'
                                  : (isPasswordVisible
                                        ? cred.password
                                        : '••••••••'),
                              style: TextStyle(
                                fontFamily: cred.password.isEmpty
                                    ? null
                                    : 'monospace',
                                color: cred.password.isEmpty
                                    ? Colors.grey
                                    : null,
                              ),
                            ),
                          ),
                          if (cred.password.isNotEmpty) ...[
                            IconButton(
                              icon: Icon(
                                isPasswordVisible
                                    ? CupertinoIcons.eye_slash
                                    : CupertinoIcons.eye,
                                size: 16,
                              ),
                              tooltip: isPasswordVisible
                                  ? context.l10n.t('hidePassword')
                                  : context.l10n.t('showPassword'),
                              onPressed: () {
                                setState(() {
                                  if (isPasswordVisible) {
                                    _visiblePasswordIndices.remove(index);
                                  } else {
                                    _visiblePasswordIndices.add(index);
                                  }
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                CupertinoIcons.doc_on_clipboard,
                                size: 16,
                              ),
                              tooltip: '复制密码',
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: cred.password),
                                );
                                _showSnack(
                                  context,
                                  context.l10n.t('wifiPasswordCopySuccess'),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(context.l10n.t('wifiPasswordTitle')),
          if (isRoot && !_isLoading && !isRootAsync.isLoading)
            IconButton(
              icon: const Icon(CupertinoIcons.refresh),
              onPressed: _loadWifiCredentials,
            ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            content,
            const SizedBox(height: 16),
            Text(
              context.l10n.t('wifiPasswordTips'),
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
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
