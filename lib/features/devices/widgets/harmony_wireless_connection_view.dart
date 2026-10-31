import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/harmony/wireless/harmony_wireless_models.dart';
import '../../../core/harmony/hdc_service_device_info.dart';
import '../../../core/providers/app_providers.dart';
import 'harmony_wireless_advanced.dart';

/// HarmonyOS HDC 无线调试入口，统一承载扫描、历史、双通道和自动重连。
class HarmonyWirelessConnectionView extends ConsumerStatefulWidget {
  const HarmonyWirelessConnectionView({super.key});

  @override
  ConsumerState<HarmonyWirelessConnectionView> createState() =>
      _HarmonyWirelessConnectionViewState();
}

class _HarmonyWirelessConnectionViewState
    extends ConsumerState<HarmonyWirelessConnectionView> {
  final _addressController = TextEditingController();
  RegisteredDevice? _selectedUsbDevice;
  bool _isChangingMode = false;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pasteAddress() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null) return;
    final normalized = normalizeHarmonyEndpoint(text);
    if (normalized != null) _addressController.text = normalized;
  }

  Future<void> _connect([String? address, String? expectedSerial]) async {
    final target = address ?? _addressController.text;
    final result = await ref
        .read(harmonyWirelessConnectionProvider.notifier)
        .connect(target, expectedSerial: expectedSerial);
    if (result.isSuccess && mounted) {
      _addressController.text = normalizeHarmonyEndpoint(target) ?? target;
      await ref.read(deviceRegistryProvider.notifier).refreshDevices();
    }
  }

  Future<void> _setTcpMode({required bool enabled}) async {
    final device = _selectedUsbDevice;
    if (device == null) return;
    setState(() => _isChangingMode = true);
    final hdc = ref.read(hdcServiceProvider);
    final result = enabled
        ? await hdc.enableTcpMode(device.preferredCommandId, port: 5555)
        : await hdc.disableTcpMode(device.preferredCommandId);
    if (!mounted) return;
    setState(() => _isChangingMode = false);
    if (result.isSuccess && enabled) {
      final ip =
          device.wifiIp ?? await hdc.getDeviceIp(device.preferredCommandId);
      if (ip != null) {
        _addressController.text = '$ip:5555';
        final expectedSerial = await hdc.getDeviceSerial(
          device.preferredCommandId,
        );
        await _connect(null, expectedSerial);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(harmonyWirelessConnectionProvider);
    final harmonyDevices = ref
        .watch(deviceRegistryProvider)
        .where((device) => device.isHarmony && device.isOnline)
        .toList();
    final usbDevices = harmonyDevices
        .where((device) => device.hasUsbConnection)
        .toList();
    final selected = _selectedUsbDevice;
    if (selected == null ||
        !usbDevices.any((device) => device.id == selected.id)) {
      _selectedUsbDevice = usbDevices.firstOrNull;
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
          const SizedBox(height: 12),
          _ConnectionSummary(devices: harmonyDevices),
          const SizedBox(height: 16),
          _buildUsbModeSection(context, usbDevices),
          const SizedBox(height: 16),
          _buildAddressSection(context, state),
          const SizedBox(height: 12),
          _EndpointSection(
            title: context.l10n.t('harmonyHistory'),
            emptyText: context.l10n.t('harmonyHistoryEmpty'),
            endpoints: state.history,
            busyAddress: state.connectingAddress,
            onConnect: _connect,
            onRemove: ref.read(harmonyWirelessConnectionProvider.notifier).removeHistory,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.t('harmonyAutoReconnect')),
            subtitle: Text(context.l10n.t('harmonyAutoReconnectDesc')),
            value: state.autoReconnect,
            onChanged: ref
                .read(harmonyWirelessConnectionProvider.notifier)
                .setAutoReconnect,
          ),
          if (state.messageKey != null || state.error != null)
            _StatusBanner(state: state),
          const Divider(height: 24),
          const HarmonyWirelessAdvanced(),
          const SizedBox(height: 8),
          Text(
            context.l10n.t('harmonyGuideTip'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsbModeSection(
    BuildContext context,
    List<RegisteredDevice> usbDevices,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.t('harmonySelectUsbDevice'),
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        if (usbDevices.isEmpty)
          Text(context.l10n.t('harmonyNoUsbDevice'))
        else ...[
          DropdownButtonFormField<RegisteredDevice>(
            initialValue: _selectedUsbDevice,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: usbDevices
                .map(
                  (device) => DropdownMenuItem(
                    value: device,
                    child: Text(
                      '${device.displayName} (${device.preferredCommandId})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _isChangingMode
                ? null
                : (device) => setState(() => _selectedUsbDevice = device),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _isChangingMode
                      ? null
                      : () => _setTcpMode(enabled: true),
                  icon: const Icon(
                    CupertinoIcons.antenna_radiowaves_left_right,
                    size: 16,
                  ),
                  label: Text(context.l10n.t('harmonyEnablePort')),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _isChangingMode
                    ? null
                    : () => _setTcpMode(enabled: false),
                child: Text(context.l10n.t('harmonyDisablePort')),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAddressSection(
    BuildContext context,
    HarmonyWirelessState state,
  ) {
    final busy = state.connectingAddress != null;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _addressController,
            enabled: !busy,
            onSubmitted: busy ? null : (_) => _connect(),
            decoration: InputDecoration(
              labelText: context.l10n.t('harmonyIpPortLabel'),
              hintText: context.l10n.t('harmonyIpPortPlaceholder'),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: context.l10n.t('paste'),
                onPressed: busy ? null : _pasteAddress,
                icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: busy ? null : () => _connect(),
          icon: const Icon(CupertinoIcons.link, size: 16),
          label: Text(context.l10n.t('harmonyConnectWireless')),
        ),
      ],
    );
  }
}

class _ConnectionSummary extends StatelessWidget {
  const _ConnectionSummary({required this.devices});
  final List<RegisteredDevice> devices;

  @override
  Widget build(BuildContext context) {
    final usb = devices.where((device) => device.hasUsbConnection).length;
    final tcp = devices.where((device) => device.hasTcpConnection).length;
    return Wrap(
      spacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.usb, size: 16),
          label: Text('${context.l10n.t('connectionUsb')}: $usb'),
        ),
        Chip(
          avatar: const Icon(CupertinoIcons.wifi, size: 16),
          label: Text('${context.l10n.t('connectionTcp')}: $tcp'),
        ),
      ],
    );
  }
}

class _EndpointSection extends StatelessWidget {
  const _EndpointSection({
    required this.title,
    required this.emptyText,
    required this.endpoints,
    required this.busyAddress,
    required this.onConnect,
    this.onRemove,
  });

  final String title;
  final String emptyText;
  final List<HarmonyWirelessEndpoint> endpoints;
  final String? busyAddress;
  final Future<void> Function(String address) onConnect;
  final Future<void> Function(String address)? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        if (endpoints.isEmpty)
          Text(emptyText, style: Theme.of(context).textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: endpoints
                .map(
                  (endpoint) => InputChip(
                    avatar: busyAddress == endpoint.address
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(CupertinoIcons.wifi, size: 15),
                    label: Text(endpoint.address),
                    onPressed: busyAddress == null
                        ? () => onConnect(endpoint.address)
                        : null,
                    onDeleted: onRemove == null
                        ? null
                        : () => onRemove!(endpoint.address),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.state});
  final HarmonyWirelessState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isError = state.error != null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (isError ? colors.errorContainer : colors.primaryContainer)
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        state.error ?? context.l10n.t(state.messageKey!),
        style: TextStyle(
          color: isError ? colors.onErrorContainer : colors.onPrimaryContainer,
        ),
      ),
    );
  }
}
