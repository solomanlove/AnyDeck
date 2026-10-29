import '../adb/wireless/adb_wireless_state.dart';

/// Android 投屏的实际 ADB 通道类型；枚举顺序同时定义自动选路优先级。
enum MirrorTransportType {
  usb('mirrorTransportUsb'),
  tcp('mirrorTransportTcp'),
  wifi('mirrorTransportWifi');

  const MirrorTransportType(this.labelKey);
  final String labelKey;

  static MirrorTransportType fromDeviceId(String deviceId) {
    if (isPhysicalUsbId(deviceId)) return usb;
    return isWirelessTlsId(deviceId) ? wifi : tcp;
  }
}
