import 'package:any_deck/core/notifications/notification_device_identity.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const phone = RegisteredDevice(
    id: '192.168.1.8:5555',
    serial: 'SERIAL_A1234',
    connections: ['USB_A', '192.168.1.8:5555'],
    customName: '工作手机',
    model: 'Pixel_9',
    status: 'device',
    isOnline: true,
  );

  test('USB and Wi-Fi share the same identity and current name', () {
    for (final route in phone.connections) {
      final identity = resolveNotificationIdentity(
        devices: [phone],
        deviceId: route,
        installationId: 'inst',
        fallbackName: 'Android device',
      );
      expect(identity.stableId, 'SERIAL_A1234');
      expect(identity.name, '工作手机');
    }
    final renamed = resolveNotificationIdentity(
      devices: [phone.copyWith(customName: '新备注')],
      deviceId: phone.id,
      installationId: 'inst',
      fallbackName: 'Android device',
      snapshot: const NotificationDeviceIdentity(
        stableId: 'SERIAL_A1234',
        name: '旧备注',
      ),
    );
    expect(renamed.name, '新备注');
  });

  test('same model with colliding suffixes gets longer identifiers', () {
    const a = NotificationDeviceIdentity(
      stableId: 'SERIAL_A1234',
      name: 'Pixel',
    );
    const b = NotificationDeviceIdentity(
      stableId: 'SERIAL_B1234',
      name: 'Pixel',
    );
    final ids = [a.stableId, b.stableId];
    expect(a.label(ids), 'Pixel · A1234');
    expect(b.label(ids), 'Pixel · B1234');
  });

  test('offline snapshot cannot be relabeled by a reused network route', () {
    final identity = resolveNotificationIdentity(
      devices: [phone],
      deviceId: phone.id,
      installationId: 'old',
      fallbackName: 'Android device',
      snapshot: const NotificationDeviceIdentity(
        stableId: 'OTHER_SERIAL',
        name: '离线手机',
      ),
    );
    expect(identity.stableId, 'OTHER_SERIAL');
    expect(identity.name, '离线手机');
    expect(
      findNotificationDevice([phone], phone.id, stableId: 'OTHER_SERIAL'),
      isNull,
    );
  });

  test('unknown hardware uses installation identity instead of IP address', () {
    final identity = resolveNotificationIdentity(
      devices: [],
      deviceId: '1.2.3.4:5555',
      serial: '1.2.3.4:5555',
      installationId: 'abcd',
      fallbackName: 'Android device',
    );
    expect(identity.stableId, 'installation:abcd');
    expect(identity.label([]), 'Android device · abcd');
  });
}
