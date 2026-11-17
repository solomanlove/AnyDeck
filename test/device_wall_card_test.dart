import 'dart:convert';
import 'dart:typed_data';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/devices/widgets/device_wall_card.dart';
import 'package:any_deck/features/devices/widgets/device_wall_phone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用真实 Theme 检查设备墙的尺寸、选择边界和截图真实性。
void main() {
  testWidgets('普通卡片保持原型手机比例，主操作和更多操作各自触发', (tester) async {
    var opens = 0;
    var infos = 0;
    var menus = 0;
    await tester.pumpWidget(
      _host(
        _card(
          onOpen: () => opens++,
          onInfo: () => infos++,
          onMore: () => menus++,
        ),
      ),
    );

    final phone = find.byType(DeviceWallPhone);
    final size = tester.getSize(phone);
    expect(size.width, 132);
    expect(size.height, closeTo(132 * 18.5 / 9, .001));
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.text('设备已就绪'), findsOneWidget);

    await tester.tap(phone);
    expect(opens, 1);
    await tester.tap(find.byType(OutlinedButton));
    expect(opens, 2);
    await tester.tap(find.text('Mi MIX 3'));
    expect(infos, 1);
    await tester.tap(find.byType(IconButton));
    expect(menus, 1);
    expect(opens, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量模式只改变选择，不打开设备，禁选卡片不响应选择', (tester) async {
    var opens = 0;
    var selected = false;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => _card(
            batchMode: true,
            selected: selected,
            onOpen: () => opens++,
            onSelected: (value) => setState(() => selected = value),
          ),
        ),
      ),
    );
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);

    await tester.tap(find.byType(DeviceWallPhone));
    await tester.pump();
    expect(selected, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(selected, isFalse);
    await tester.tap(find.text('Mi MIX 3'));
    await tester.pump();
    expect(selected, isTrue);
    expect(opens, 0);

    await tester.pumpWidget(
      _host(
        _card(
          batchMode: true,
          selectable: false,
          onSelected: (_) => fail('不可选择的卡片不应触发回调'),
          onOpen: () => opens++,
        ),
      ),
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    await tester.tap(find.byType(DeviceWallPhone));
    expect(opens, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('在线仅显示传入的真实截图，离线不展示历史截图', (tester) async {
    final screenshot = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(_host(_card(screenshot: screenshot)));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('设备已就绪'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _host(_card(online: false, screenshot: screenshot)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('设备未连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} 长设备名与放大字体在窄卡片内自然增高', (tester) async {
      for (final batch in [false, true]) {
        await tester.pumpWidget(
          _host(
            _card(
              name: 'sdk_gphone16k_arm64 Android Emulator',
              statusLabel: 'USB connected',
              actionLabel: 'Reconnect',
              batchMode: batch,
            ),
            width: 146,
            brightness: brightness,
            textScale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final card = tester.getRect(find.byType(DeviceWallCard));
        final phone = tester.getRect(find.byType(DeviceWallPhone));
        expect(phone.left, greaterThanOrEqualTo(card.left));
        expect(phone.right, lessThanOrEqualTo(card.right));
        expect(find.byType(Checkbox), batch ? findsOneWidget : findsNothing);
      }
    });
  }
}

DeviceWallCard _card({
  String name = 'Mi MIX 3',
  String statusLabel = 'USB 已连接',
  String actionLabel = '投屏',
  bool online = true,
  bool batchMode = false,
  bool selected = false,
  bool selectable = true,
  Uint8List? screenshot,
  VoidCallback? onOpen,
  VoidCallback? onInfo,
  VoidCallback? onMore,
  ValueChanged<bool>? onSelected,
}) => DeviceWallCard(
  name: name,
  systemVersion: 'Android 15',
  statusLabel: statusLabel,
  brand: 'Xiaomi',
  coverTitle: online ? '设备已就绪' : '设备未连接',
  coverHint: online ? '点击打开投屏' : '通过 USB 或无线连接',
  actionLabel: actionLabel,
  ipAddress: '192.168.1.219',
  online: online,
  batchMode: batchMode,
  selected: selected,
  selectable: selectable,
  screenshot: screenshot,
  onOpen: onOpen,
  onInfo: onInfo,
  onMore: onMore,
  onSelected: onSelected,
);

Widget _host(
  Widget child, {
  double width = 166,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: buildAppTheme(brightness),
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  builder: (context, content) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: content!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);
