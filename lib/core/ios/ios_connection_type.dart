/// usbmuxd 报告的 iOS 连接通道；未知值使用空集合，不按 UDID 猜测 USB。
enum IosConnectionType {
  usb,
  network;

  /// 同时兼容 go-ios CLI 和 Rust DAL 的字段值。
  static IosConnectionType? parse(Object? value) =>
      switch (value?.toString().toLowerCase()) {
        'usb' => usb,
        'network' => network,
        _ => null,
      };
}
