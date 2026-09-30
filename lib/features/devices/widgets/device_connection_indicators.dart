import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/modules/registered_device_model.dart';

/// 设备标识旁的只读 USB / TCP / TLS 通道状态，不提供连接操作。
/// [device] 为合并后的设备；消费点击以避免触发外层设备行的概览导航。
class DeviceConnectionIndicators extends StatelessWidget {
  const DeviceConnectionIndicators({super.key, required this.device});
  final RegisteredDevice device;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () {},
        onDoubleTap: () {},
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (device.hasUsbConnection)
              _indicator(context, 'connectionUsb', Icons.usb, const Color(0xFF26A69A)),
            if (device.hasTcpConnection)
              _indicator(context, 'connectionTcp', CupertinoIcons.link, const Color(0xFF00ACC1)),
            if (device.hasWifiDebuggingConnection)
              _indicator(context, 'connectionWirelessDebug', CupertinoIcons.wifi, const Color(0xFF43A047)),
          ],
        ),
      ),
    );
  }

  Widget _indicator(BuildContext context, String labelKey, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: context.l10n.t(labelKey),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}
