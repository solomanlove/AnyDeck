import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/ios/ios_app_info.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_icon_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/features/apps/controller/app_favorites_controller.dart';
import 'package:any_deck/features/apps/widgets/apps_alphabet_sidebar.dart';
import 'package:any_deck/features/ios/controller/ios_apps_controller.dart';
import 'package:any_deck/features/ios/ios_apps_tab.dart';
import 'package:any_deck/features/ios/model/ios_apps_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const apps = [
  IosAppInfo(bundleId: 'com.example.chat', name: '微信', version: '1.0'),
  IosAppInfo(bundleId: 'com.apple.Preferences', name: 'Settings', system: true),
  IosAppInfo(bundleId: 'com.apple.store', name: 'Apple Store'),
  IosAppInfo(bundleId: 'com.example.123', name: '123'),
];

class FakeCommands extends IosCommandService {
  final pending = <String, Completer<List<IosAppInfo>>>{};
  List<IosAppInfo> result = apps;

  @override
  Future<List<IosAppInfo>> listApps(String udid) async =>
      pending[udid]?.future ?? result;
}

class FakeIcons extends IosIconService {
  final requests = <IosIconRequest>[];
  Completer<Map<String, String>>? pending;

  @override
  Future<Map<String, String>> fetchIcons(
    String udid,
    List<String> bundleIds, {
    IosIconRequest? request,
  }) async {
    requests.add(request!);
    return pending?.future ?? {};
  }
}

Widget page(String udid, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: IosAppsTab(
          device: AdbDevice(id: udid, status: 'device', isIos: true),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('combines category, bundle id, Chinese, pinyin and initials', () {
    List<String> result(String query, IosAppFilter category) => filterIosApps(
      apps,
      query: query,
      category: category,
      favorites: {'com.apple.Preferences', 'com.example.chat'},
    ).map((app) => app.bundleId).toList();
    expect(result('', IosAppFilter.user), hasLength(3));
    expect(result('', IosAppFilter.system), ['com.apple.Preferences']);
    expect(result(' COM.APPLE ', IosAppFilter.all), hasLength(2));
    for (final query in ['微信', 'weixin', 'wx']) {
      expect(result(query, IosAppFilter.favorites), ['com.example.chat']);
    }
    expect(result('missing', IosAppFilter.all), isEmpty);
    expect(iosAppFirstLetter(apps.first), 'W');
    expect(iosAppFirstLetter(apps.last), '#');
  });

  test('iOS favorites persist without modifying Android favorites', () async {
    SharedPreferences.setMockInitialValues({
      'apps.favoritePackages.v1': ['android.existing'],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(iosAppFavoritesProvider.future);
    await container
        .read(iosAppFavoritesProvider.notifier)
        .toggle('com.example.chat');
    expect(await container.read(appFavoritesProvider.future), {
      'android.existing',
    });
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    expect(await restored.read(iosAppFavoritesProvider.future), {
      'com.example.chat',
    });
    await restored
        .read(iosAppFavoritesProvider.notifier)
        .toggle('com.example.chat');
    expect(restored.read(iosAppFavoritesProvider).value, isEmpty);
  });

  testWidgets('category, search, favorites and narrow dark layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        iosCommandServiceProvider.overrideWithValue(FakeCommands()),
        iosIconServiceProvider.overrideWithValue(FakeIcons()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: page('phone')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'initial layout');
    expect(find.text('微信'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.byType(AppsAlphabetSidebar), findsOneWidget);
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('微信'), findsNothing);
    final uninstall = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    expect(uninstall.onPressed, isNull);
    await tester.tap(find.byTooltip('Add Favorite').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorites ✨'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete Favorite'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wx');
    await tester.pumpAndSettle();
    expect(find.text('微信'), findsOneWidget);
    expect(find.text('Apple Store'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(container.read(iosAppsSearchHistoryProvider).value, contains('wx'));
    expect(tester.takeException(), isNull, reason: 'search and favorites');
    tester.view.physicalSize = const Size(640, 600);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: page('phone', brightness: Brightness.dark),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching device ignores a late app response', (tester) async {
    final commands = FakeCommands();
    final old = Completer<List<IosAppInfo>>();
    commands.pending['old'] = old;
    final container = ProviderContainer(
      overrides: [
        iosCommandServiceProvider.overrideWithValue(commands),
        iosIconServiceProvider.overrideWithValue(FakeIcons()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: page('old')),
    );
    await tester.pump();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: page('new')),
    );
    await tester.pumpAndSettle();
    old.complete([const IosAppInfo(bundleId: 'old.app', name: 'Old App')]);
    await tester.pumpAndSettle();
    expect(find.text('Old App'), findsNothing);
    expect(find.text('微信'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alphabet sidebar jumps to an offscreen app', (tester) async {
    final commands = FakeCommands()
      ..result = [
        for (var i = 0; i < 60; i++)
          IosAppInfo(bundleId: 'com.example.a$i', name: 'Alpha $i'),
        const IosAppInfo(bundleId: 'com.example.z', name: 'Zulu'),
      ];
    final container = ProviderContainer(
      overrides: [
        iosCommandServiceProvider.overrideWithValue(commands),
        iosIconServiceProvider.overrideWithValue(FakeIcons()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: page('phone')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zulu'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(AppsAlphabetSidebar),
        matching: find.text('Z'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zulu').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving the page cancels pending icon extraction', (
    tester,
  ) async {
    final icons = FakeIcons()..pending = Completer<Map<String, String>>();
    final container = ProviderContainer(
      overrides: [
        iosCommandServiceProvider.overrideWithValue(FakeCommands()),
        iosIconServiceProvider.overrideWithValue(icons),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: page('phone')),
    );
    await tester.pumpAndSettle();
    expect(icons.requests.single.cancelled, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(icons.requests.single.cancelled, isTrue);
    icons.pending!.complete({'com.example.chat': '/unused/icon.png'});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
