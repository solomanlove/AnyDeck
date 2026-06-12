part of '../dashboard_screen.dart';

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
                  Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: context.l10n.t(
                                    'qrImageCaptionPrefix',
                                  ),
                                ),
                                const TextSpan(text: ' '),
                                TextSpan(
                                  text: context.l10n.t(
                                    'qrImageCaptionDevice',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const TextSpan(text: '\n'),
                                TextSpan(
                                  text: context.l10n.t(
                                    'qrImageCaptionAction',
                                  ),
                                ),
                              ],
                            ),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(
                              color: const Color(0xff202124),
                              fontWeight: FontWeight.w600,
                              height: 1.32,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 20,
                                  offset: const Offset(1, 4),
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
                    ),
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
                            prefixIcon: const Icon(CupertinoIcons.link),
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
                            prefixIcon: const Icon(CupertinoIcons.number),
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isPairing ? null : _manualPair,
                          icon: const Icon(CupertinoIcons.link),
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
