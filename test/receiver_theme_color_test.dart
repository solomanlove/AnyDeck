import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/airplay/airplay_server_service.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:any_deck/core/dlna/dlna_player_bridge.dart';
import 'package:any_deck/core/dlna/dlna_renderer_service.dart';
import 'package:any_deck/features/receivers/receiver_dashboard_tab.dart';
import 'package:any_deck/features/receivers/widgets/receiver_service_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = AirPlaySessionData(
  id: 1,
  serverName: 'AnyDeck 测试 AirPlay',
  rtspPort: 7000,
  videoPort: 7100,
  status: AirPlayServerStatus.mirroring,
);

/// 名称查询及保存只更新测试状态，不触发持久化、名称探测或广播。
class _Settings extends AppSettingsController {
  int nameWrites = 0;

  @override
  AppSettings build() => const AppSettings(
    airplayServerName: 'AnyDeck 测试 AirPlay',
    dlnaServerName: 'AnyDeck 测试 DLNA',
  );

  @override
  Future<String> receiverNameForStart(
    String protocol, {
    bool alreadyRunning = false,
  }) async => state.dlnaServerName;

  @override
  Future<void> setAirplayServerName(
    String value, {
    bool broadcast = true,
  }) async {
    nameWrites++;
    state = state.copyWith(airplayServerName: value);
  }

  @override
  Future<void> setDlnaServerName(String value, {bool broadcast = true}) async {
    nameWrites++;
    state = state.copyWith(dlnaServerName: value);
  }
}

/// 可控 AirPlay 生命周期，不启动 Bonjour、解码器或窗口。
class _AirPlay extends AirPlayServerNotifier {
  int starts = 0;
  int stops = 0;

  @override
  AirPlaySessionData? build() => _session;

  void setRunning(bool value) => state = value ? _session : null;

  @override
  Future<void> startServer({
    String? name,
    int rtspPort = 7000,
    int videoPort = 7100,
  }) async {
    starts++;
    setRunning(true);
  }

  @override
  Future<void> stopServer() async {
    stops++;
    setRunning(false);
  }
}

/// 只模拟可观察状态和启停完成，不创建 HTTP、SSDP 或播放器资源。
class _Dlna extends DlnaRendererService {
  _Dlna() : super.forTest();
  bool running = true;
  int starts = 0;
  int stops = 0;

  @override
  bool get isRunning => running;
  @override
  bool get isBusy => false;
  @override
  bool get hasActiveMedia => running;

  void setRunning(bool value) {
    running = value;
    notifyListeners();
  }

  @override
  Future<void> start() async {
    starts++;
    setRunning(true);
  }

  @override
  Future<void> stop() async {
    stops++;
    setRunning(false);
  }
}

/// 两个真实协议卡片共享动态 Theme，刻意移除全局 Cupertino 主色兜底。
Future<ValueNotifier<AppThemeColor>> _pumpCards(
  WidgetTester tester, {
  required Brightness brightness,
  required _Settings settings,
  required _AirPlay airplay,
  required _Dlna dlna,
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final color = ValueNotifier(AppThemeColor.blue);
  addTearDown(color.dispose);
  final container = ProviderContainer(
    overrides: [
      appSettingsProvider.overrideWith(() => settings),
      airplaySessionProvider.overrideWith(() => airplay),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(dlna.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ValueListenableBuilder<AppThemeColor>(
        valueListenable: color,
        builder: (context, value, child) => MaterialApp(
          theme: buildAppTheme(brightness, themeColor: value).copyWith(
            platform: platform,
            cupertinoOverrideTheme: const CupertinoThemeData(
              applyThemeToAll: false,
            ),
          ),
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: child,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(child: AirPlayReceiverCard()),
                  Expanded(child: DlnaReceiverCard(service: dlna)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return color;
}

Finder _switch(String protocol) => find.byKey(Key('${protocol}ReceiverSwitch'));

/// 直接断言最终 Canvas 的轨道绘制，防止只验证参数却仍回退系统绿色。
void _expectSwitch(
  WidgetTester tester,
  String protocol,
  AppThemeColor color, {
  bool enabled = true,
}) {
  final finder = _switch(protocol);
  final control = tester.widget<Switch>(finder);
  final theme = Theme.of(tester.element(finder));
  expect(control.value, enabled);
  expect(control.activeTrackColor, color.color);
  expect(control.activeThumbColor, theme.colorScheme.onPrimary);
  expect(theme.cupertinoOverrideTheme?.applyThemeToAll, isFalse);
  if (enabled) {
    final paint = find.descendant(
      of: finder,
      matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter != null,
      ),
    );
    expect(paint, findsOneWidget);
    expect(paint, paints..rrect(color: color.color));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(
      DlnaPlayerBridge.channel,
      (_) async => null,
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(DlnaPlayerBridge.channel, null);
  });

  for (final brightness in Brightness.values) {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      testWidgets('接收页两个真实开关在 $platform $brightness 独立换色并保留输入', (tester) async {
        final settings = _Settings();
        final airplay = _AirPlay();
        final dlna = _Dlna();
        final color = await _pumpCards(
          tester,
          brightness: brightness,
          platform: platform,
          settings: settings,
          airplay: airplay,
          dlna: dlna,
        );
        final airplayState = tester.state(find.byType(AirPlayReceiverCard));
        final dlnaState = tester.state(find.byType(DlnaReceiverCard));
        final fields = find.byType(TextField);
        final input = tester.widget<TextField>(fields.first).controller!;
        await tester.enterText(fields.first, '尚未提交的 AnyDeck 名称');
        await tester.pump();

        for (final value in [AppThemeColor.blue, AppThemeColor.purple]) {
          color.value = value;
          await tester.pumpAndSettle();
          _expectSwitch(tester, 'airplay', value);
          _expectSwitch(tester, 'dlna', value);
          expect(
            tester.state(find.byType(AirPlayReceiverCard)),
            same(airplayState),
          );
          expect(tester.state(find.byType(DlnaReceiverCard)), same(dlnaState));
          expect(
            tester.widget<TextField>(fields.first).controller,
            same(input),
          );
          expect(input.text, '尚未提交的 AnyDeck 名称');
          expect(settings.nameWrites, 0);
          expect(
            [airplay.starts, airplay.stops, dlna.starts, dlna.stops],
            [0, 0, 0, 0],
          );
          for (final card in tester.widgetList<ReceiverServiceCard>(
            find.byType(ReceiverServiceCard),
          )) {
            expect(card.statusColor, AppPalette.primary);
          }
        }

        airplay.setRunning(false);
        dlna.setRunning(false);
        await tester.pumpAndSettle();
        _expectSwitch(tester, 'airplay', AppThemeColor.purple, enabled: false);
        _expectSwitch(tester, 'dlna', AppThemeColor.purple, enabled: false);
        expect(input.text, '尚未提交的 AnyDeck 名称');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
