import 'package:any_deck/core/notifications/notification_click_target.dart';
import 'package:any_deck/core/notifications/notification_database.dart';
import 'package:any_deck/core/notifications/notification_device_identity.dart';
import 'package:any_deck/core/notifications/notification_models.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Database extends NotificationDatabase {
  const _Database() : super('unused');
  @override
  Future<NotificationSource> readSource(
    String installationId,
    int userId,
  ) async =>
      NotificationSource(installationId: installationId, androidUserId: userId);
  @override
  Future<NotificationSource?> resolveSource(String alias) async =>
      NotificationSource(
        installationId: alias == 'wifi_new' ? 'source_a' : 'source_b',
        androidUserId: 10,
      );
}

void main() {
  test(
    'stable serial takes priority over an IP now owned by another phone',
    () async {
      const devices = [
        RegisteredDevice(
          id: 'old_ip',
          serial: 'SERIAL_B',
          status: 'device',
          isOnline: true,
        ),
        RegisteredDevice(
          id: 'new_ip',
          serial: 'SERIAL_A',
          status: 'device',
          isOnline: true,
        ),
      ];
      final device = await resolveNotificationClickDevice(
        devices: devices,
        database: const _Database(),
        deviceId: 'old_ip',
        deviceSerial: 'SERIAL_A',
      );
      expect(device?.id, 'new_ip');
      final missing = await resolveNotificationClickDevice(
        devices: devices,
        database: const _Database(),
        deviceId: 'old_ip',
        deviceSerial: 'DELETED',
      );
      expect(missing, isNull);
    },
  );

  test(
    'without serial a click must match installation and Android user',
    () async {
      const devices = [
        RegisteredDevice(id: 'old_ip', status: 'device', isOnline: true),
        RegisteredDevice(id: 'wifi_new', status: 'device', isOnline: true),
      ];
      final device = await resolveNotificationClickDevice(
        devices: devices,
        database: const _Database(),
        deviceId: 'old_ip',
        deviceSerial: 'installation:source_a',
        installationId: 'source_a',
        userId: 10,
      );
      expect(device?.id, 'wifi_new');
      final wrongUser = await resolveNotificationClickDevice(
        devices: devices,
        database: const _Database(),
        deviceId: 'old_ip',
        deviceSerial: 'installation:source_a',
        installationId: 'source_a',
        userId: 0,
      );
      expect(wrongUser, isNull);
    },
  );

  test('snapshot hardware identity survives unrelated serial arguments', () {
    final identity = resolveNotificationIdentity(
      devices: [],
      deviceId: 'old_ip',
      serial: 'NEW_SERIAL',
      installationId: 'old',
      fallbackName: 'Android device',
      snapshot: const NotificationDeviceIdentity(
        stableId: 'OLD_SERIAL',
        name: 'Old phone',
      ),
    );
    expect(identity.stableId, 'OLD_SERIAL');
  });
}
