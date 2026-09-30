import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/modules/device_registry_providers.dart';
import '../../../core/providers/modules/registered_device_model.dart';
import '../../../core/providers/modules/service_providers.dart';

/// 鸿蒙设备 HDC 无线调试视图。
///
/// 支持检测已连接的鸿蒙 USB 设备、切换 TCP/IP 5555 调试端口，
/// 以及通过指定的局域网 IP:端口 发起无线连接。
class HarmonyWirelessPairingView extends ConsumerStatefulWidget {
  const HarmonyWirelessPairingView({super.key});

  @override
  ConsumerState<HarmonyWirelessPairingView> createState() =>
      _HarmonyWirelessPairingViewState();
}

class _HarmonyWirelessPairingViewState
    extends ConsumerState<HarmonyWirelessPairingView> {
  final _ipPortController = TextEditingController();
  RegisteredDevice? _selectedDevice;
  bool _isProcessing = false;
  String _statusMessage = '';
  bool _isError = false;

  @override
  void dispose() {
    _ipPortController.dispose();
    super.dispose();
  }

  void _onDeviceSelected(RegisteredDevice? device) {
    setState(() {
      _selectedDevice = device;
      if (device != null) {
        final ip = device.wifiIp ?? '';
        if (ip.isNotEmpty) {
          _ipPortController.text = '$ip:5555';
        }
      }
    });
  }

  Future<void> _enableTcpMode() async {
    final device = _selectedDevice;
    if (device == null) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = '正在开启 5555 调试端口...';
      _isError = false;
    });

    final hdc = ref.read(hdcServiceProvider);
    final result = await hdc.enableTcpMode(device.id, port: 5555);

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      if (result.isSuccess) {
        _statusMessage = context.l10n.t('harmonyEnablePortSuccess');
        _isError = false;
      } else {
        _statusMessage = '开启失败: ${result.message}';
        _isError = true;
      }
    });
  }

  Future<void> _connectWireless() async {
    final ipPort = _ipPortController.text.trim();
    if (ipPort.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = '正在尝试无线连接 $ipPort...';
      _isError = false;
    });

    final hdc = ref.read(hdcServiceProvider);
    final result = await hdc.connectWireless(ipPort);

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      if (result.isSuccess) {
        _statusMessage = context.l10n.t('harmonyConnectSuccess');
        _isError = false;
        // 刷新设备列表
        ref.read(deviceRegistryProvider.notifier).refreshDevices();
      } else {
        _statusMessage = '${context.l10n.t('harmonyConnectFailed')}: ${result.message}';
        _isError = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDevices = ref.watch(deviceRegistryProvider);
    final harmonyDevices =
        allDevices.where((d) => d.isHarmony && d.isOnline).toList();

    // 如果未选择过设备且当前有在线的鸿蒙设备，默认选中第一台
    if (_selectedDevice == null && harmonyDevices.isNotEmpty) {
      _selectedDevice = harmonyDevices.first;
      final ip = _selectedDevice?.wifiIp ?? '';
      if (ip.isNotEmpty && _ipPortController.text.isEmpty) {
        _ipPortController.text = '$ip:5555';
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.t('harmonyWirelessDesc'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // 1. 已接入的鸿蒙设备选择
          Text(
            context.l10n.t('harmonySelectDevice'),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          if (harmonyDevices.isNotEmpty) ...[
            DropdownButtonFormField<RegisteredDevice>(
              initialValue: harmonyDevices.contains(_selectedDevice)
                  ? _selectedDevice
                  : harmonyDevices.first,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: harmonyDevices.map((d) {
                return DropdownMenuItem(
                  value: d,
                  child: Text(
                    '${d.displayName} (${d.id})',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _isProcessing ? null : _onDeviceSelected,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(
                      CupertinoIcons.antenna_radiowaves_left_right,
                      size: 16,
                    ),
                    label: Text(context.l10n.t('harmonyEnablePort')),
                    onPressed: _isProcessing ? null : _enableTcpMode,
                  ),
                ),
              ],
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                context.l10n.t('harmonyNoUsbDevice'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          const SizedBox(height: 20),
          // 2. 目标 IP 与端口输入
          Text(
            context.l10n.t('harmonyIpPortLabel'),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipPortController,
                  enabled: !_isProcessing,
                  decoration: InputDecoration(
                    hintText: context.l10n.t('harmonyIpPortPlaceholder'),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(CupertinoIcons.link, size: 16),
                label: Text(context.l10n.t('harmonyConnectWireless')),
                onPressed: _isProcessing ? null : _connectWireless,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 3. 状态反馈与使用提示
          if (_statusMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _isError
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isError ? Colors.redAccent : Colors.green,
                ),
              ),
              child: Text(
                _statusMessage,
                style: TextStyle(
                  fontSize: 12,
                  color: _isError ? Colors.redAccent : Colors.green.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            context.l10n.t('harmonyGuideTip'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
