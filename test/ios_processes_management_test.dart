import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/ios/ios_app_info.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_icon_service.dart';
import 'package:any_deck/core/ios/ios_process_info.dart';
import 'package:any_deck/core/ios/ios_process_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/ios/controller/ios_processes_controller.dart';
import 'package:any_deck/features/ios/ios_processes_tab.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _items = [
  IosProcessInfo(
    pid: 10,
    name: 'UserRunner',
    isApplication: true,
    executablePath: '/Apps/A.app/Runner',
    app: IosAppInfo(bundleId: 'com.example.user', name: 'User App'),
  ),
  IosProcessInfo(
    pid: 2,
    name: 'SystemRunner',
    isApplication: true,
    app: IosAppInfo(
      bundleId: 'com.example.system',
      name: 'System App',
      system: true,
    ),
  ),
  IosProcessInfo(pid: 3, name: 'UnknownDaemon', isApplication: false),
];

/// 可控异步数据源，测试不依赖 go-ios 或真机连接。
class _Service extends IosProcessService {
  _Service() : super(IosCommandService(), 'a');
  List<IosProcessInfo> items = _items;
  Completer<List<IosProcessInfo>>? pending;
  bool fail = false;
  bool failKill = false;
  int reads = 0, closes = 0, kills = 0;
  final metadataRefreshes = <bool>[];
  @override
  Future<List<IosProcessInfo>> read({bool refreshApps = false}) async {
    reads++;
    metadataRefreshes.add(refreshApps);
    if (fail) throw StateError('offline');
    return pending?.future ?? items;
  }

  @override
  Future<void> kill(IosProcessInfo expected) async {
    kills++;
    if (failKill) throw StateError('denied');
  }

  @override
  void close() {
    closes++;
    super.close();
  }
}

class _Icons extends IosIconService {
  final calls = <List<String>>[];
  IosIconRequest? request;
  @override
  Future<Map<String, String>> fetchIcons(
    String udid,
    List<String> bundleIds, {
    IosIconRequest? request,
  }) async {
    calls.add(bundleIds);
    this.request = request;
    return {};
  }
}

Widget _page(
  _Service service,
  _Icons icons, {
  String language = 'en',
  Brightness brightness = Brightness.light,
  bool Function()? online,
}) => ProviderScope(
  overrides: [
    iosProcessServiceProvider.overrideWith((ref, id) => service),
    iosIconServiceProvider.overrideWithValue(icons),
    deviceOnlineProvider.overrideWith((ref, id) => online?.call() ?? true),
  ],
  child: MaterialApp(
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(brightness: brightness),
    home: const Scaffold(
      body: IosProcessesTab(
        device: AdbDevice(id: 'a', status: 'device', isIos: true),
      ),
    ),
  ),
);

Future<void> _menu(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('ios-process-10')),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('$language $brightness 窄窗口工具栏/表格，指标为未知值', (tester) async {
        tester.view.physicalSize = const Size(420, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _page(
            _Service(),
            _Icons(),
            language: language,
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('User App · UserRunner'), findsOneWidget);
        expect(
          find.text(language == 'zh' ? '未获取' : 'Not collected'),
          findsWidgets,
        );
        expect(find.text('0.0'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('搜索与分类、仅应用组合，PID 排序和清除筛选', (tester) async {
    await tester.pumpWidget(_page(_Service(), _Icons()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('User').first);
    await tester.pumpAndSettle();
    expect(find.text('User App · UserRunner'), findsOneWidget);
    expect(find.text('UnknownDaemon'), findsNothing);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('User App · UserRunner'), findsNothing);
    await tester.enterText(find.byType(TextField), 'COM.EXAMPLE.USER');
    await tester.pumpAndSettle();
    expect(find.text('User App · UserRunner'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Apps Only'));
    await tester.pumpAndSettle();
    expect(find.text('UnknownDaemon'), findsNothing);
    expect(find.text('System App · SystemRunner'), findsOneWidget);
    await tester.tap(find.text('PID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PID'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('User App · UserRunner')).dy,
      lessThan(tester.getTopLeft(find.text('System App · SystemRunner')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('轮询不重入、图标去重、失败保留数据、关闭刷新与离页取消', (tester) async {
    final service = _Service();
    final icons = _Icons();
    await tester.pumpWidget(_page(service, icons));
    await tester.pumpAndSettle();
    expect(service.reads, 1);
    expect(icons.calls, hasLength(1));
    service.pending = Completer();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 9));
    expect(service.reads, 2);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IosProcessesTab)),
    );
    await container.read(iosProcessesProvider('a').notifier).refresh();
    expect(service.reads, 2);
    service.pending!.complete(_items);
    service.pending = null;
    await tester.pumpAndSettle();
    service.fail = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('User App · UserRunner'), findsOneWidget);
    expect(find.textContaining('Refresh failed;'), findsOneWidget);
    expect(icons.calls, hasLength(1));
    expect(service.metadataRefreshes.every((flag) => !flag), isTrue);
    await tester.tap(find.text('Auto refresh (3s)'));
    await tester.pumpAndSettle();
    final count = service.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(service.reads, count);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(service.closes, greaterThan(0));
    expect(icons.request!.cancelled, isTrue);
  });

  testWidgets('断线取消会话和图标，离页后延迟刷新结果不回写', (tester) async {
    final service = _Service();
    final icons = _Icons();
    var online = true;
    await tester.pumpWidget(_page(service, icons, online: () => online));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IosProcessesTab)),
    );
    service.pending = Completer();
    await tester.pump(const Duration(seconds: 3));
    online = false;
    container.invalidate(deviceOnlineProvider('a'));
    await tester.pumpAndSettle();
    expect(service.closes, greaterThan(0));
    expect(icons.request!.cancelled, isTrue);
    service.pending!.complete(_items);
    await tester.pumpAndSettle();
    expect(find.text('User App · UserRunner'), findsNothing);
    expect(
      find.text('Device offline, cannot read process list'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('右键复制、取消/确认结束、异常恢复和自动刷新设置恢复', (tester) async {
    final service = _Service();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_page(service, _Icons()));
    await tester.pumpAndSettle();
    await _menu(tester);
    await tester.tap(find.text('Copy Bundle ID'));
    await tester.pumpAndSettle();
    expect(copied, 'com.example.user');
    await _menu(tester);
    await tester.tap(find.text('Kill process'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.kills, 0);
    service.failKill = true;
    await _menu(tester);
    await tester.tap(find.text('Kill process'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(service.kills, 1);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IosProcessesTab)),
    );
    expect(container.read(iosProcessesProvider('a')).busy, isFalse);
    expect(container.read(iosProcessesProvider('a')).autoRefresh, isTrue);
    expect(find.textContaining('denied'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('结束确认期间断线，确认不得操作原设备', (tester) async {
    final service = _Service();
    var online = true;
    await tester.pumpWidget(_page(service, _Icons(), online: () => online));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IosProcessesTab)),
    );
    await _menu(tester);
    await tester.tap(find.text('Kill process'));
    await tester.pumpAndSettle();
    online = false;
    container.invalidate(deviceOnlineProvider('a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(service.kills, 0);
    expect(service.closes, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('长列表仅创建可见行', (tester) async {
    final service = _Service()
      ..items = List.generate(
        1000,
        (i) => IosProcessInfo(pid: i + 1, name: 'Process $i'),
      );
    await tester.pumpWidget(_page(service, _Icons()));
    await tester.pumpAndSettle();
    expect(
      find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('ios-process-'),
          )
          .evaluate()
          .length,
      lessThan(30),
    );
    expect(tester.takeException(), isNull);
  });
}
