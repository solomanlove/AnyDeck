import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/modules/service_providers.dart';

/// HarmonyOS 开发板专用 UART 与 Remote HDC Server 高级设置。
class HarmonyWirelessAdvanced extends ConsumerStatefulWidget {
  const HarmonyWirelessAdvanced({super.key});

  @override
  ConsumerState<HarmonyWirelessAdvanced> createState() =>
      _HarmonyWirelessAdvancedState();
}

class _HarmonyWirelessAdvancedState
    extends ConsumerState<HarmonyWirelessAdvanced> {
  final _hostController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '18710');
  final _uartController = TextEditingController();
  bool _serverRunning = false;
  bool _busy = false;
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _uartController.dispose();
    super.dispose();
  }

  Future<void> _toggleServer(bool enabled) async {
    setState(() => _busy = true);
    try {
      final server = ref.read(hdcRemoteServerProvider);
      if (enabled) {
        await server.start(
          host: _hostController.text.trim(),
          port: int.tryParse(_portController.text.trim()) ?? 0,
        );
      } else {
        await server.stop();
      }
      if (!mounted) return;
      setState(() {
        _serverRunning = server.isRunning;
        _message = context.l10n.t(
          _serverRunning ? 'harmonyRemoteStarted' : 'harmonyRemoteStopped',
        );
        _error = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = '${context.l10n.t('harmonyRemoteFailed')}: $error';
        _error = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runUart({required bool checkOnly}) async {
    setState(() => _busy = true);
    final result = checkOnly
        ? await ref.read(hdcServiceProvider).checkUart(_uartController.text)
        : await ref.read(hdcServiceProvider).connectAnyUart();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result.isSuccess ? result.stdout.trim() : result.message;
      _error = !result.isSuccess;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(context.l10n.t('harmonyAdvanced')),
      subtitle: Text(context.l10n.t('harmonyAdvancedDesc')),
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.t('harmonyRemoteServer')),
          subtitle: Text(context.l10n.t('harmonyRemoteServerDesc')),
          value: _serverRunning,
          onChanged: _busy ? null : _toggleServer,
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hostController,
                enabled: !_serverRunning && !_busy,
                decoration: InputDecoration(
                  labelText: context.l10n.t('harmonyListenAddress'),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _portController,
                enabled: !_serverRunning && !_busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.t('port'),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            context.l10n.t('harmonyUartBoardOnly'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _uartController,
                enabled: !_busy,
                decoration: InputDecoration(
                  hintText: context.l10n.t('harmonyUartPlaceholder'),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy || _uartController.text.trim().isEmpty
                  ? null
                  : () => _runUart(checkOnly: true),
              child: Text(context.l10n.t('harmonyUartCheck')),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _runUart(checkOnly: false),
              icon: const Icon(CupertinoIcons.link, size: 16),
              label: Text(context.l10n.t('harmonyUartConnect')),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _message!,
              style: TextStyle(
                fontSize: 12,
                color: _error ? colors.error : colors.primary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
