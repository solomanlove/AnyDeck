import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:any_deck/core/ios/ios_connection_type.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/airplay/airplay_mirror_target.dart';
import 'package:flutter_test/flutter_test.dart';

RegisteredDevice device({
  required String id,
  required bool isIos,
  required bool isOnline,
  String? model,
  String? customName,
  Set<IosConnectionType> connections = const {},
}) => RegisteredDevice(
  id: id,
  model: model,
  customName: customName,
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

  test('多设备并发 AirPlay：按型号精准合并已有行并为未登记设备生成列表行', () {
    final rootSession = const AirPlaySessionData(
      id: 1001,
      serverName: 'AnyDeck-AirPlay',
      rtspPort: 7000,
      videoPort: 7100,
      status: AirPlayServerStatus.mirroring,
      width: 500,
      height: 1080,
      clientDeviceId: 'AA:BB:CC:DD:EE:01',
      clientModel: 'iPhone10,3',
      clientName: 'iPhone',
      additionalSessions: [
        AirPlaySessionData(
          id: 1002,
          serverName: 'AnyDeck-AirPlay #2',
          rtspPort: 7001,
          videoPort: 7101,
          status: AirPlayServerStatus.mirroring,
          width: 1179,
          height: 2556,
          clientDeviceId: 'AA:BB:CC:DD:EE:02',
          clientModel: 'iPhone16,1',
          clientName: 'Shijie iPhone 15 Pro',
        ),
      ],
    );

    final merged = mergeAirPlayDevicesIntoList([
      device(
        id: 'udid-iphone-x',
        model: 'iPhone X',
        isIos: true,
        isOnline: true,
        connections: const {IosConnectionType.network},
      ),
      device(
        id: 'udid-iphone-6s',
        model: 'iPhone 6s',
        isIos: true,
        isOnline: false,
      ),
    ], rootSession);

    expect(merged.devices.length, 3);
    expect(merged.sessionByDeviceId['udid-iphone-x']?.id, 1001);
    expect(
      merged.sessionByDeviceId['airplay-AA:BB:CC:DD:EE:02']?.id,
      1002,
    );
  });
}
