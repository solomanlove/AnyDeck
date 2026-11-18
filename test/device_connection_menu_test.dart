import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/devices/widgets/device_connection_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _buttonKey = Key('deviceConnectionButton');
const _usbHintKey = Key('deviceConnectionUsbHint');
const _actions = ['pair', 'tcp', 'share'];
const _icons = [LucideIcons.wifi, LucideIcons.link, LucideIcons.users];

/// 打开真实 PopupMenu 路由验证连接入口，不启动设备发现、CLI 或连接对话框。
void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('连接菜单图标、分隔、锚点与三项回调 $language ${brightness.name}', (
        tester,
      ) async {
        final selections = <String>[];
        final copy = _copy(language);
        await _pumpMenu(
          tester,
          language: language,
          brightness: brightness,
          onSelected: selections.add,
        );
        final button = tester.getRect(find.byKey(_buttonKey));
        expect(find.text(copy.connect), findsOneWidget);
        expect(find.byTooltip(copy.connect), findsOneWidget);
        expect(find.byType(PopupMenuItem<String>), findsNothing);

        for (var index = 0; index < _actions.length; index++) {
          await _openMenu(tester);
          final surface = _menuSurface();
          final menu = tester.getRect(surface);
          _expectAnchoredMenu(menu, button, 900);
          expect(find.byType(PopupMenuItem<String>), findsNWidgets(4));
          final entries = tester.widgetList<PopupMenuItem<String>>(
            find.byType(PopupMenuItem<String>),
          );
          expect(
            entries.where((entry) => entry.enabled).map((entry) => entry.value),
            _actions,
          );

          final textLeft = <double>[];
          for (var itemIndex = 0; itemIndex < _actions.length; itemIndex++) {
            final item = _item(_actions[itemIndex]);
            final label = find.descendant(
              of: item,
              matching: find.text(copy.labels[itemIndex]),
            );
            expect(label, findsOneWidget);
            expect(
              find.descendant(
                of: item,
                matching: find.byIcon(_icons[itemIndex]),
              ),
              findsOneWidget,
            );
            textLeft.add(tester.getTopLeft(label).dx);
          }
          expect(textLeft[0], closeTo(textLeft[1], 0.1));
          expect(textLeft[1], closeTo(textLeft[2], 0.1));
          _expectThemedSurface(tester, surface);
          _expectUsbFooter(tester, copy.usb);

          // 提示不是第四个连接动作，点击后菜单应继续保持打开。
          await tester.tap(find.byKey(_usbHintKey));
          await tester.pumpAndSettle();
          expect(selections, _actions.take(index).toList());
          expect(_item('pair'), findsOneWidget);

          await tester.tap(_item(_actions[index]));
          await tester.pumpAndSettle();
          expect(selections, _actions.take(index + 1).toList());
          expect(find.byType(PopupMenuItem<String>), findsNothing);
          expect(tester.takeException(), isNull);
        }

        await _openMenu(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuItem<String>), findsNothing);
        await _openMenu(tester);
        await tester.tapAt(const Offset(20, 500));
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuItem<String>), findsNothing);
        expect(selections, _actions);
        expect(tester.takeException(), isNull);
      });

      testWidgets('320px放大字体连接菜单完整可读且不溢出 $language ${brightness.name}', (
        tester,
      ) async {
        final selections = <String>[];
        final copy = _copy(language);
        await _pumpMenu(
          tester,
          language: language,
          brightness: brightness,
          width: 320,
          textScale: 1.6,
          showLabel: false,
          onSelected: selections.add,
        );
        final button = tester.getRect(find.byKey(_buttonKey));
        expect(find.text(copy.connect), findsNothing);
        expect(find.byTooltip(copy.connect), findsOneWidget);
        await _openMenu(tester);
        final menu = tester.getRect(_menuSurface());
        _expectAnchoredMenu(menu, button, 320, allowScreenClamp: true);
        expect(menu.bottom, lessThanOrEqualTo(700));
        for (final label in [...copy.labels, copy.usb]) {
          final text = find.text(label);
          expect(text, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(text);
          expect(paragraph.didExceedMaxLines, isFalse, reason: label);
          final rect = tester.getRect(text);
          expect(rect.left, greaterThanOrEqualTo(menu.left));
          expect(rect.right, lessThanOrEqualTo(menu.right));
          expect(rect.bottom, lessThanOrEqualTo(menu.bottom));
        }
        _expectUsbFooter(tester, copy.usb);
        await tester.tap(find.byKey(_usbHintKey));
        await tester.pumpAndSettle();
        expect(selections, isEmpty);
        expect(_item('pair'), findsOneWidget);
        await tester.tap(_item('tcp'));
        await tester.pumpAndSettle();
        expect(selections, ['tcp']);
        expect(find.byType(PopupMenuItem<String>), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Finder _item(String action) => find.byKey(Key('deviceConnection-$action'));

Finder _menuSurface() =>
    find.ancestor(of: _item('pair'), matching: find.byType(Material)).first;

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(_buttonKey));
  await tester.pumpAndSettle();
  expect(_item('pair'), findsOneWidget);
}

void _expectAnchoredMenu(
  Rect menu,
  Rect button,
  double width, {
  bool allowScreenClamp = false,
}) {
  if (allowScreenClamp) {
    // 原生菜单在触及屏幕安全边距时可向右避让，宽窗口仍必须严格对齐按钮。
    expect(menu.right, inInclusiveRange(button.right, width));
  } else {
    expect(menu.right, closeTo(button.right, 1));
  }
  expect(menu.top, greaterThanOrEqualTo(button.bottom));
  expect(menu.left, greaterThanOrEqualTo(0));
  expect(menu.right, lessThanOrEqualTo(width));
}

void _expectThemedSurface(WidgetTester tester, Finder surface) {
  final material = tester.widget<Material>(surface);
  final theme = Theme.of(tester.element(surface));
  expect(material.color, theme.appColors.panelSurface);
  expect(material.surfaceTintColor, Colors.transparent);
  expect(material.elevation, greaterThan(0));
  expect(material.shape, isA<RoundedRectangleBorder>());
  final shape = material.shape! as RoundedRectangleBorder;
  expect(shape.borderRadius, isNot(BorderRadius.zero));
  expect(shape.side.color, theme.colorScheme.outlineVariant);
}

void _expectUsbFooter(WidgetTester tester, String label) {
  final hint = find.byKey(_usbHintKey);
  expect(hint, findsOneWidget);
  expect(find.text(label), findsOneWidget);
  final disabled = tester
      .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
      .where((entry) => !entry.enabled);
  expect(disabled, hasLength(1));
  expect(disabled.single.value, isNull);
  final divider = find.descendant(of: hint, matching: find.byType(Divider));
  expect(divider, findsOneWidget);
  expect(
    tester.getTopLeft(divider).dy,
    greaterThanOrEqualTo(tester.getBottomLeft(_item('share')).dy),
  );
  expect(
    tester.getTopLeft(find.text(label)).dy,
    greaterThanOrEqualTo(tester.getBottomLeft(divider).dy),
  );
  expect(
    tester.widget<Divider>(divider).color,
    Theme.of(tester.element(divider)).colorScheme.outlineVariant,
  );
}

({String connect, List<String> labels, String usb}) _copy(String language) =>
    language == 'zh'
    ? (
        connect: '连接设备',
        labels: ['无线配对', '通过 IP 连接', '加入共享设备'],
        usb: 'USB 设备连接并授权后自动出现',
      )
    : (
        connect: 'Connect device',
        labels: ['Wireless pairing', 'Connect by IP', 'Join shared device'],
        usb: 'USB devices appear after connection and authorization',
      );

Future<void> _pumpMenu(
  WidgetTester tester, {
  required String language,
  required Brightness brightness,
  required ValueChanged<String> onSelected,
  double width = 900,
  double textScale = 1,
  bool showLabel = true,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDeviceWorkspaceTheme(buildAppTheme(brightness)),
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DeviceConnectionMenu(
              onSelected: onSelected,
              showLabel: showLabel,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
