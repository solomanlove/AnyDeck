import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/adb/adb_result.dart';
import '../../../core/network/network_device_address.dart';
import 'tcpip_connection_guide.dart';

/// 手动 TCP/IP 连接表单。通过 connect 接入现有连接服务；成功返回 AdbResult。
/// 控制器由弹窗 State 持有，随退出动画后的卸载释放，失败时保留输入供重试。
class TcpipConnectionDialog extends StatefulWidget {
  const TcpipConnectionDialog({super.key, required this.connect});

  final Future<AdbResult> Function(String address) connect;

  @override
  State<TcpipConnectionDialog> createState() => _TcpipConnectionDialogState();
}

class _TcpipConnectionDialogState extends State<TcpipConnectionDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_connecting || !_formKey.currentState!.validate()) return;
    final address = NetworkDeviceAddress.tryParse(_controller.text)!;
    setState(() {
      _connecting = true;
      _error = null;
    });
    var completed = false;
    try {
      final result = await widget.connect(address.address);
      if (!mounted) return;
      if (result.isSuccess) {
        completed = true;
        Navigator.of(context).pop(result);
        return;
      }
      setState(() => _error = result.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted && !completed) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.t('connectDevice')),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.t('tcpipReadyHint')),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controller,
                autofocus: true,
                enabled: !_connecting,
                decoration: InputDecoration(
                  labelText: l10n.t('tcpipAddressLabel'),
                  hintText: l10n.t('tcpipAddressExample'),
                  helperText: l10n.t('tcpipAddressHint'),
                  helperMaxLines: 3,
                  errorMaxLines: 3,
                ),
                validator: (value) =>
                    NetworkDeviceAddress.tryParse(value ?? '') == null
                    ? l10n.t('tcpipInvalidAddress')
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${l10n.t('wirelessFailed')}\n$_error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              const TcpipConnectionGuide(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton.icon(
          onPressed: _connecting ? null : _submit,
          icon: _connecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link),
          label: Text(l10n.t(_connecting ? 'wirelessConnecting' : 'connect')),
        ),
      ],
    );
  }
}
