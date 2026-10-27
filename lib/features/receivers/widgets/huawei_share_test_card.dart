import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/nearby_share/share_core_client.dart';

/// 华为分享单文件收发自测入口；状态仅由当前卡片持有，离开页面即回收原生进程。
class HuaweiShareTestCard extends StatefulWidget {
  const HuaweiShareTestCard({super.key, this.client = const ShareCoreClient()});

  final ShareCoreClient client;

  @override
  State<HuaweiShareTestCard> createState() => _HuaweiShareTestCardState();
}

class _HuaweiShareTestCardState extends State<HuaweiShareTestCard> {
  final _local = TextEditingController();
  final _broadcast = TextEditingController();
  final _peer = TextEditingController();
  final _port = TextEditingController(text: '44800');
  final _peers = <ShareCorePeer>[];
  StreamSubscription<ShareCorePeer>? _scan;
  ShareCoreTransfer? _transfer;
  bool _ready = false;
  bool _scanning = false;
  bool _busy = false;
  bool _choosing = false;
  String? _status;
  String? _receivedPath;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final capabilities = await widget.client.probe();
      if (!capabilities.discovery) throw StateError('discovery unavailable');
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final candidates = [
        for (final interface in interfaces)
          for (final address in interface.addresses)
            if (!address.isLinkLocal) (interface.name, address.address),
      ];
      if (!mounted) return;
      final selected =
          candidates.where((entry) => entry.$1 == 'en0').firstOrNull ??
          candidates.firstOrNull;
      if (selected != null) {
        _local.text = selected.$2;
        final octets = selected.$2.split('.');
        if (octets.length == 4) {
          // 仅作为常见 /24 网络的初值，用户可按真实子网修改。
          _broadcast.text = '${octets.take(3).join('.')}.255';
        }
      }
      setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    }
  }

  InternetAddress _ipv4(String value) {
    final address = InternetAddress.tryParse(value.trim());
    if (address == null || address.type != InternetAddressType.IPv4) {
      throw const FormatException('Invalid IPv4 address');
    }
    return address;
  }

  Future<void> _discover() async {
    if (!_ready || _busy || _choosing || _scanning) return;
    try {
      final local = _ipv4(_local.text);
      final broadcast = _ipv4(_broadcast.text);
      setState(() {
        _peers.clear();
        _scanning = true;
        _status = null;
      });
      _scan = widget.client
          .discover(
            localAddress: local,
            broadcastAddress: broadcast,
            duration: const Duration(seconds: 30),
          )
          .listen(
            (peer) {
              if (!mounted) return;
              setState(() {
                _peers.removeWhere((item) => item.address == peer.address);
                _peers.add(peer);
                if (_peer.text.isEmpty) {
                  _peer.text = peer.address.address;
                  _port.text = '${peer.port}';
                }
              });
            },
            onError: (Object error) {
              if (mounted) {
                setState(() {
                  _status = '$error';
                  _scanning = false;
                });
              }
            },
            onDone: () {
              if (mounted) setState(() => _scanning = false);
            },
          );
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = '$error';
          _scanning = false;
        });
      }
    }
  }

  Future<void> _run(Future<ShareCoreTransfer> Function() start) async {
    if (!_ready || _busy) return;
    await _scan?.cancel();
    _scan = null;
    setState(() {
      _busy = true;
      _scanning = false;
      _status = null;
      _receivedPath = null;
    });
    try {
      final transfer = await start();
      _transfer = transfer;
      if (!mounted) {
        transfer.cancel();
        return;
      }
      final result = await transfer.result;
      if (!mounted) return;
      setState(() {
        _status = result['event'] == 'file_sent'
            ? context.l10n.t('shareTestSent')
            : context.l10n.t('shareTestReceived');
        _receivedPath = result['path'] as String?;
      });
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      _transfer = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_choosing || _busy) return;
    setState(() => _choosing = true);
    XFile? selected;
    try {
      selected = await openFile();
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
    if (selected == null || !mounted) return;
    final selectedPath = selected.path;
    await _run(() async {
      final port = int.tryParse(_port.text.trim());
      if (port == null || port < 1 || port > 65535) {
        throw const FormatException('Invalid TCP port');
      }
      return widget.client.sendFileForTest(
        localAddress: _ipv4(_local.text),
        peer: ShareCorePeer(
          address: _ipv4(_peer.text),
          port: port,
          name: _peer.text.trim(),
        ),
        file: File(selectedPath),
      );
    });
  }

  Future<void> _receive() async {
    if (_choosing || _busy) return;
    setState(() => _choosing = true);
    String? parent;
    try {
      parent = await getDirectoryPath();
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
    if (parent == null || !mounted) return;
    await _run(
      () => widget.client.receiveFileForTest(
        localAddress: _ipv4(_local.text),
        broadcastAddress: _ipv4(_broadcast.text),
        peerAddress: _ipv4(_peer.text),
        outputDirectory: Directory(
          '$parent/AnyDeck-Share-'
          '${DateTime.now().microsecondsSinceEpoch}',
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_scan?.cancel());
    _transfer?.cancel();
    _local.dispose();
    _broadcast.dispose();
    _peer.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.share_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  l10n.t('shareTestTitle'),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l10n.t('shareTestLimit'), style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _addressField(_local, l10n.t('shareTestLocalIp')),
                _addressField(_broadcast, l10n.t('shareTestBroadcastIp')),
                _addressField(_peer, l10n.t('shareTestPeerIp')),
                _addressField(_port, l10n.t('shareTestPeerPort'), width: 100),
              ],
            ),
            if (_peers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final peer in _peers)
                    ActionChip(
                      label: Text('${peer.name} (${peer.address.address})'),
                      onPressed: () => setState(() {
                        _peer.text = peer.address.address;
                        _port.text = '${peer.port}';
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _ready && !_busy && !_choosing && !_scanning
                      ? _discover
                      : null,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(l10n.t('shareTestDiscover')),
                ),
                FilledButton.icon(
                  onPressed: _ready && !_busy && !_choosing ? _send : null,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(l10n.t('shareTestSend')),
                ),
                FilledButton.tonalIcon(
                  onPressed: _ready && !_busy && !_choosing ? _receive : null,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(l10n.t('shareTestReceive')),
                ),
                if (_busy)
                  TextButton(
                    onPressed: () => _transfer?.cancel(),
                    child: Text(l10n.t('shareTestCancel')),
                  ),
                if (_busy || _scanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              SelectableText(_status!, style: theme.textTheme.bodySmall),
            ],
            if (_receivedPath != null) ...[
              const SizedBox(height: 4),
              SelectableText(_receivedPath!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _addressField(
    TextEditingController controller,
    String label, {
    double width = 170,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}
