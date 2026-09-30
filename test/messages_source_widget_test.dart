import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/notifications/mac_notification_bridge.dart';
import 'package:any_deck/core/notifications/notification_database.dart';
import 'package:any_deck/core/notifications/notification_device_identity.dart';
import 'package:any_deck/core/notifications/notification_forwarding_client.dart';
import 'package:any_deck/core/notifications/notification_forwarding_service.dart';
import 'package:any_deck/core/notifications/notification_models.dart';
import 'package:any_deck/core/notifications/notification_providers.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/messages/presentation/controller/messages_controller.dart';
import 'package:any_deck/features/messages/presentation/messages_tab.dart';
import 'package:any_deck/features/messages/presentation/widgets/messages_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = AdbDevice(id: 'phone_a', status: 'device');
const _b = AdbDevice(id: 'phone_b', status: 'device');

class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => const [
    RegisteredDevice(
      id: 'phone_a',
      serial: 'SERIAL_A',
      customName: '工作手机',
      status: 'device',
      isOnline: true,
    ),
    RegisteredDevice(
      id: 'phone_b',
      serial: 'SERIAL_B',
      customName: '私人手机',
      status: 'device',
      isOnline: true,
    ),
  ];
}

class _Packages extends PackagesNotifier {
  _Packages(super.deviceId);
  @override
  AsyncValue<List<AdbPackage>> build() => const AsyncData([]);
}

class _Client extends NotificationForwardingClient {
  _Client() : super(AdbService(executable: 'unused'));
  final aStatus = Completer<NotificationSessionStatus>();
  @override
  Future<int> getCurrentUser(String deviceId) async => 0;
  @override
  Future<NotificationSessionStatus> getStatus(String deviceId, int userId) =>
      deviceId == _a.id
      ? aStatus.future
      : Future.value(
          const NotificationSessionStatus(
            isSharingEnabled: true,
            isPermissionGranted: true,
            installationId: 'b',
            androidUserId: 0,
          ),
        );
}

NotificationMessage _message(String source, int id) => NotificationMessage(
  id: id,
  installationId: source,
  androidUserId: 0,
  notificationKey: '$id',
  packageName: 'chat',
  appName: '微信',
  title: '$source-message-$id',
  content: '正文',
  postTime: DateTime(2026),
  receivedTime: DateTime(2026),
);

class _Database extends NotificationDatabase {
  _Database() : super('unused');
  final links = <String>[];
  @override
  Future<NotificationSource> readSource(String installationId, int userId) async =>
      NotificationSource(installationId: installationId, androidUserId: userId);

  @override
  Future<NotificationSource?> resolveSource(String alias) async =>
      NotificationSource(
        installationId: alias == 'SERIAL_A' ? 'a' : 'b',
        androidUserId: 0,
      );
  @override
  Future<void> linkSource(
    Iterable<String> aliases,
    String installationId,
    int userId, {
    NotificationDeviceIdentity? identity,
  }) async {
    links.add(installationId);
  }

  @override
  Future<List<NotificationMessage>> queryMessages(
    String installationId,
    int userId, {
    String? query,
    String? packageName,
    int offset = 0,
    int limit = 50,
  }) async => [_message(installationId, installationId == 'a' ? 1 : 2)];
}

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: theme,
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'late A status cannot replace B messages after switching devices',
    (tester) async {
      final client = _Client();
      final database = _Database();
      final bridge = MacNotificationBridge();
      final service = NotificationForwardingService(
        client: client,
        databaseFuture: Future.value(database),
        bridge: bridge,
        settingsGetter: () => const AppSettings(),
        appNameResolver: (_, _) => null,
        appIconPathResolver: (_, _) => null,
        deviceIdentityResolver: (_, serial, _) =>
            NotificationDeviceIdentity(stableId: serial, name: ''),
        deviceLabelResolver: (identity) => identity.label([]),
      );
      final container = ProviderContainer(
        overrides: [
          deviceRegistryProvider.overrideWith(_Registry.new),
          notificationForwardingClientProvider.overrideWithValue(client),
          notificationDatabaseProvider.overrideWith((ref) async => database),
          notificationForwardingServiceProvider.overrideWithValue(service),
          notificationForwardingStateChangesProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
          notificationMessageChangesProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
          for (final device in [_a, _b]) ...[
            deviceOnlineProvider(device.id).overrideWithValue(true),
            packagesProvider(device.id)
                .overrideWith(() => _Packages(device.id)),
          ],
          for (final serial in ['SERIAL_A', 'SERIAL_B'])
            forwardingEnabledProvider(serial)
                .overrideWith((ref) async => false),
        ],
      );
      addTearDown(() {
        service.dispose();
        bridge.dispose();
        container.dispose();
      });
      Future<void> show(AdbDevice device) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _app(MessagesTab(device: device)),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(_a);
      expect(find.text('a-message-1'), findsOneWidget);
      await show(_b);
      expect(find.text('b-message-2'), findsOneWidget);
      expect(find.text('a-message-1'), findsNothing);
      expect(find.text('私人手机 · AL_B'), findsNWidgets(2));
      client.aStatus.complete(
        const NotificationSessionStatus(
          isSharingEnabled: true,
          isPermissionGranted: true,
          installationId: 'a',
          androidUserId: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('b-message-2'), findsOneWidget);
      expect(find.text('a-message-1'), findsNothing);
      expect(database.links, ['b']);
      container.read(messageClickTargetProvider.notifier).state = (
        deviceId: _b.id, serial: 'SERIAL_B', installationId: 'old_b', userId: 0,
      );
      await tester.pumpAndSettle();
      expect(find.text('old_b-message-2'), findsOneWidget);
      await tester.tap(find.text('正在查看历史来源，返回当前手机消息'));
      await tester.pumpAndSettle();
      expect(find.text('b-message-2'), findsOneWidget);
      expect(find.text('old_b-message-2'), findsNothing);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'clicked older message is visible with source in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            packagesProvider(_a.id).overrideWith(() => _Packages(_a.id)),
          ],
        );
        addTearDown(container.dispose);
        container.read(targetMessageIdProvider.notifier).state = 80;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _app(
              MessagesListView(
                messages: List.generate(100, (i) => _message('a', i)),
                deviceId: _a.id,
                deviceLabel: '工作手机 · A123',
                isOnline: false,
              ),
              theme: dark ? ThemeData.dark() : ThemeData.light(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('a-message-80').hitTestable(), findsOneWidget);
        expect(find.text('工作手机 · A123'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
