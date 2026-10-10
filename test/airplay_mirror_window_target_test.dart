import 'package:any_deck/core/ios/ios_connection_type.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/airplay/airplay_mirror_target.dart';
import 'package:flutter_test/flutter_test.dart';

RegisteredDevice device({
  required String id,
  required bool isIos,
  required bool isOnline,
  Set<IosConnectionType> connections = const {},
}) => RegisteredDevice(
  id: id,
  status: isOnline ? 'device' : 'offline',
  isOnline: isOnline,
  isIos: isIos,
  iosConnectionTypes: connections,
);

void main() {
  test('AirPlay 优先复用在线 USB iOS 投屏窗口', () {
    final target = resolveAirPlayMirrorTarget([
      device(id: 'android', isIos: false, isOnline: true),
      device(
        id: 'wifi-ios',
        isIos: true,
        isOnline: true,
        connections: const {IosConnectionType.network},
      ),
      device(
        id: 'usb-ios',
        isIos: true,
        isOnline: true,
        connections: const {IosConnectionType.usb},
      ),
    ]);

    expect(target?.id, 'usb-ios');
  });

  test('没有 USB 时回退在线 iOS，离线设备不参与', () {
    final target = resolveAirPlayMirrorTarget([
      device(
        id: 'offline-usb',
        isIos: true,
        isOnline: false,
        connections: const {IosConnectionType.usb},
      ),
      device(
        id: 'wifi-ios',
        isIos: true,
        isOnline: true,
        connections: const {IosConnectionType.network},
      ),
    ]);

    expect(target?.id, 'wifi-ios');
    expect(resolveAirPlayMirrorTarget(const []), isNull);
  });
}
