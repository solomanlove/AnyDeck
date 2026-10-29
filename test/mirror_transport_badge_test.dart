import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/window/mirror/mirror_device_info_overlay.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/mirror_transport_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用真实项目 Theme 和本地化测试标签，覆盖已加载、加载中和失败的概览数据。
Widget _app(
  Widget child, {
  String locale = 'zh',
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: buildAppTheme(brightness),
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}

void main() {
  const labels = {
    'zh': ['USB 投屏', 'TCP 投屏', 'Wi-Fi 投屏'],
    'en': ['USB mirroring', 'TCP mirroring', 'Wi-Fi mirroring'],
  };
  for (final locale in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final type in MirrorTransportType.values) {
        testWidgets('$locale $brightness ${type.name} 标签位于设备名称右侧', (
          tester,
        ) async {
          await tester.pumpWidget(
            _app(
              MirrorDeviceInfoCard(
                overview: DeviceOverview.fromJson({'name': 'SM-F9710'}),
                fallbackName: 'phone',
                transport: type,
              ),
              locale: locale,
              brightness: brightness,
            ),
          );
          final label = labels[locale]![type.index];
          expect(find.text(label), findsOneWidget);
          expect(
            tester.getTopLeft(find.byKey(const Key('mirrorTransportBadge'))).dx,
            greaterThan(tester.getTopRight(find.text('SM-F9710')).dx),
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('长名称在窄卡片内省略，投屏方式保持完整且无溢出', (tester) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 250,
          child: MirrorDeviceInfoCard(
            overview: DeviceOverview.fromJson({
              'name': '很长的三星手机自定义名称 SM-F9710 Fold',
            }),
            fallbackName: 'phone',
            transport: MirrorTransportType.wifi,
          ),
        ),
      ),
    );
    expect(find.text('Wi-Fi 投屏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('概览尚未加载或读取失败时仍显示当前会话方式', (tester) async {
    final overview = StreamController<DeviceOverview>();
    final container = ProviderContainer(
      overrides: [
        deviceOverviewProvider(
          '192.168.1.8:5555',
        ).overrideWith((ref) => overview.stream),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await overview.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          const MirrorDeviceInfoOverlay(
            deviceId: '192.168.1.8:5555',
            deviceName: 'SM-F9710',
            transport: MirrorTransportType.tcp,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('TCP 投屏'), findsOneWidget);
    overview.addError(StateError('unavailable'));
    await tester.pump();
    expect(find.text('TCP 投屏'), findsOneWidget);
    expect(find.text('USB 投屏'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('没有 Android 会话类型时不猜测 USB 或显示错误标签', (tester) async {
    await tester.pumpWidget(
      _app(
        MirrorDeviceInfoCard(
          overview: DeviceOverview.fromJson({'name': 'iPhone'}),
          fallbackName: 'phone',
        ),
      ),
    );
    expect(find.byKey(const Key('mirrorTransportBadge')), findsNothing);
  });
}
