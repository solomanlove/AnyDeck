import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/window/mirror/widget/mirror_status_view.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/fusion_mode_preference.dart';
import 'package:any_deck/features/apps/widgets/fusion_mode_setting_row.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _AdbFake extends AdbService {
  _AdbFake() : super(executable: 'adb');

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async => const AdbResult(exitCode: 0, stdout: '35', stderr: '');
}

class _StoreFake implements FusionModeStore {
  bool? value;

  @override
  Future<bool?> read(String key) async => value;

  @override
  Future<void> write(String key, bool enabled) async {
    value = enabled;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android 14 开关默认开启，关闭后同设备视图显示关闭', (tester) async {
    final store = _StoreFake();
    final preference = FusionModePreference(_AdbFake(), store: store);
    final device = RegisteredDevice(
      id: 'usb-1',
      status: 'device',
      isOnline: true,
      serial: 'PHONE-1',
      sdkVersion: 35,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceOnlineProvider('usb-1').overrideWith((ref) => true),
          fusionModePreferenceProvider.overrideWithValue(preference),
          deviceFusionModeProvider(
            'usb-1',
          ).overrideWith((ref) => preference.resolve('usb-1', device: device)),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: Scaffold(body: FusionModeSettingRow(deviceId: 'usb-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<CupertinoSwitch>(find.byKey(const Key('fusionModeSwitch')))
          .value,
      isTrue,
    );
    expect(find.textContaining('只影响之后新开的应用窗口'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fusionModeSwitch')));
    await tester.pumpAndSettle();
    expect(store.value, isFalse);
    expect(
      tester
          .widget<CupertinoSwitch>(find.byKey(const Key('fusionModeSwitch')))
          .value,
      isFalse,
    );
  });

  testWidgets('副屏失败时显示用户主动选择的普通投屏入口', (tester) async {
    var selectedPrimary = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: MirrorStatusView(
            rawErrorMessage: 'Fusion startup failed',
            onRetry: () {},
            onPrimaryMirror: () => selectedPrimary = true,
          ),
        ),
      ),
    );

    expect(find.text('改用普通投屏'), findsOneWidget);
    await tester.tap(find.text('改用普通投屏'));
    expect(selectedPrimary, isTrue);
  });
}
