part of 'dashboard_screen.dart';

/// 设备表格行渲染，和面板容器分离，便于维护列结构。
extension _DeviceListPanelRows on _DeviceListPanelState {
  Widget _buildDeviceRow(
    BuildContext context,
    RegisteredDevice device,
    bool isSelected,
    bool isCompact,
  ) {
    return Material(
      color: isSelected
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.4)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(userClearedDeviceSelectionProvider.notifier).state = false;
          ref.read(selectedDeviceProvider.notifier).select(device.toAdbDevice);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              if (!isCompact) ...[
                SizedBox(
                  width: 45,
                  child: Checkbox(
                    value: device.isChecked,
                    onChanged: (_) {
                      ref
                          .read(deviceRegistryProvider.notifier)
                          .toggleCheck(device.id);
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],
              const SizedBox(width: 10),
              _buildIdentifierCell(device),
              const SizedBox(width: 10),
              _buildNameCell(context, device),
              const SizedBox(width: 10),
              _buildStatusCell(context, device),
              const SizedBox(width: 10),
              _buildActionsCell(context, device),
              if (!isCompact) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 40,
                  child: Icon(Icons.chevron_right, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentifierCell(RegisteredDevice device) {
    return Expanded(
      flex: 3,
      child: Row(
        children: [
          const Icon(Icons.info, color: Color(0xFF26A69A), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              device.connectionMethodDisplay,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_hasUsbConnection(device)) ...[
            const SizedBox(width: 4),
            const Icon(Icons.usb, color: Color(0xFF26A69A), size: 16),
          ],
          if (_hasNetworkConnection(device)) ...[
            const SizedBox(width: 4),
            const Icon(Icons.wifi, color: Color(0xFF26A69A), size: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildNameCell(BuildContext context, RegisteredDevice device) {
    return Expanded(
      flex: 3,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFC8E6C9), width: 1),
              ),
              child: Text(
                device.displayName,
                style: const TextStyle(
                  color: Color(0xFF2E7D32),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: 16,
            onPressed: () => _showRenameDialog(context, device),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCell(BuildContext context, RegisteredDevice device) {
    return Expanded(
      flex: 2,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getStatusBgColor(device.status),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _getStatusText(context, device.status),
            style: TextStyle(
              color: _getStatusTextColor(device.status),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionsCell(BuildContext context, RegisteredDevice device) {
    return Expanded(
      flex: 2,
      child: Row(
        children: [
          if (device.isNetwork) ...[
            IconButton(
              icon: Icon(
                device.isOnline ? Icons.link_off : Icons.link,
                color: device.isOnline ? Colors.red : Colors.green,
              ),
              tooltip: device.isOnline
                  ? context.l10n.t('disconnect')
                  : context.l10n.t('connect'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _runAdbAction(
                context,
                ref,
                device.isOnline
                    ? ref
                          .read(deviceRegistryProvider.notifier)
                          .disconnectDevice(device.id)
                    : ref
                          .read(deviceRegistryProvider.notifier)
                          .connectDevice(device.id),
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: context.l10n.t('delete'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              ref.read(deviceRegistryProvider.notifier).removeDevice(device.id);
            },
          ),
        ],
      ),
    );
  }

  bool _hasUsbConnection(RegisteredDevice device) {
    if (device.connections.isEmpty) {
      return !device.isNetwork;
    }
    return device.connections.any(
      (connection) =>
          !(connection.contains(':') ||
              connection.contains('.') ||
              connection == '127.0.0.1'),
    );
  }

  bool _hasNetworkConnection(RegisteredDevice device) {
    if (device.connections.isEmpty) {
      return device.isNetwork;
    }
    return device.connections.any(
      (connection) =>
          connection.contains(':') ||
          connection.contains('.') ||
          connection == '127.0.0.1',
    );
  }
}
