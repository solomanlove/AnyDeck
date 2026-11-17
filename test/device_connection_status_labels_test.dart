import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/ios/ios_connection_type.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/devices/widgets/device_connection_indicators.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _columnKey = Key('connection-status-column');
const _android = RegisteredDevice(
  id: 'phone-usb-serial',
  status: 'device',
  isOnline: true,
  connections: ['phone-usb-serial', '192.168.1.20:5555', '192.168.1.20:41117'],
);
const _androidLabels = ['USB', 'TCP/IP', 'Wi-Fi', 'AirPlay'];
const _androidFullKeys = [
  'deviceWorkspaceUsbConnected',
  'connectionTcp',
  'connectionWirelessDebug',
  'deviceWorkspaceAirplay',
];

/// 在实际80px连接列内检查完整通道、可访问语义及父级批量选择手势。
void main() {
  // testWidgets 默认管理 SemanticsHandle，避免额外句柄晚于框架检查才释放。
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('$language ${brightness.name} $scale 倍字号80px列完整展示全部连接', (
          tester,
        ) async {
          var selected = 0;
          await _pumpStatus(
            tester,
            device: _android,
            language: language,
            brightness: brightness,
            textScale: scale,
            isAirplayMirroring: true,
            onTap: () => selected++,
          );
          final copy = AppLocalizations(Locale(language));
          final fullLabels = _androidFullKeys.map(copy.t).toList();
          expect(find.bySemanticsLabel(fullLabels.join(', ')), findsOneWidget);
          final column = tester.getRect(find.byKey(_columnKey));
          expect(column.width, 80);
          double? previousBottom;
          for (var i = 0; i < _androidLabels.length; i++) {
            final label = find.text(_androidLabels[i]);
            expect(label, findsOneWidget);
            expect(find.byTooltip(fullLabels[i]), findsOneWidget);
            _expectCompleteLabel(tester, label, column);
            final rect = tester.getRect(label);
            if (previousBottom != null) {
              expect(rect.top, greaterThanOrEqualTo(previousBottom));
            }
            previousBottom = rect.bottom;
            final text = tester.widget<Text>(label);
            expect(
              text.style?.color,
              Theme.of(tester.element(label)).appColors.success,
            );
            // 标签只有状态表达，点击任一通道仍选中所属设备行。
            await tester.tap(label);
            await tester.pump();
            expect(selected, i + 1);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('连接更新移除TCP后保留USB和Wi-Fi且清理旧Tooltip与语义', (tester) async {
    await _pumpStatus(tester, device: _android);
    expect(find.text('TCP/IP'), findsOneWidget);
    final updated = _android.copyWith(
      connections: ['phone-usb-serial', '192.168.1.20:41117'],
    );
    await _pumpStatus(tester, device: updated);
    expect(find.text('USB'), findsOneWidget);
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('TCP/IP'), findsNothing);
    final copy = AppLocalizations(const Locale('zh'));
    expect(find.byTooltip(copy.t('connectionTcp')), findsNothing);
    expect(
      find.bySemanticsLabel(
        '${copy.t('deviceWorkspaceUsbConnected')}, '
        '${copy.t('connectionWirelessDebug')}',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS USB与网络语义同时保留，AirPlay不会替代调试连接', (tester) async {
    await _pumpStatus(
      tester,
      device: _android.copyWith(
        isIos: true,
        iosConnectionTypes: {IosConnectionType.usb, IosConnectionType.network},
      ),
      language: 'en',
      isAirplayMirroring: true,
    );
    final copy = AppLocalizations(const Locale('en'));
    for (final label in ['USB', 'Wi-Fi', 'AirPlay']) {
      expect(find.text(label), findsOneWidget);
    }
    final full = [
      'deviceWorkspaceUsbConnected',
      'connectionIosNetwork',
      'deviceWorkspaceAirplay',
    ].map(copy.t).toList();
    for (final label in full) {
      expect(find.byTooltip(label), findsOneWidget);
    }
    expect(find.bySemanticsLabel(full.join(', ')), findsOneWidget);
    expect(find.text('TCP/IP'), findsNothing);
    expect(find.byTooltip(copy.t('connectionWirelessDebug')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['zh', 'en']) {
    testWidgets('$language 离线与未授权不显示历史通道，未知iOS不猜测USB', (tester) async {
      final copy = AppLocalizations(Locale(language));
      final cases = [
        (
          _android.copyWith(status: 'offline', isOnline: false),
          'deviceOffline',
        ),
        (
          _android.copyWith(status: 'unauthorized', isOnline: false),
          'deviceUnauthorizedLabel',
        ),
        (
          _android.copyWith(isIos: true, iosConnectionTypes: {}),
          'connectionUnknown',
        ),
      ];
      for (final (device, labelKey) in cases) {
        var selections = 0;
        await _pumpStatus(
          tester,
          device: device,
          language: language,
          textScale: 1.6,
          onTap: () => selections++,
        );
        final label = find.text(copy.t(labelKey));
        expect(label, findsOneWidget);
        expect(find.bySemanticsLabel(copy.t(labelKey)), findsOneWidget);
        _expectCompleteLabel(
          tester,
          label,
          tester.getRect(find.byKey(_columnKey)),
        );
        for (final channel in _androidLabels) {
          expect(find.text(channel), findsNothing);
        }
        await tester.tap(label);
        await tester.pump();
        expect(selections, 1);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('离线设备仍在AirPlay会话时仅显示AirPlay', (tester) async {
    await _pumpStatus(
      tester,
      device: _android.copyWith(status: 'offline', isOnline: false),
      isAirplayMirroring: true,
    );
    expect(find.text('AirPlay'), findsOneWidget);
    for (final label in ['USB', 'TCP/IP', 'Wi-Fi']) {
      expect(find.text(label), findsNothing);
    }
    expect(
      find.bySemanticsLabel(
        AppLocalizations(const Locale('zh')).t('deviceWorkspaceAirplay'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('$language ${brightness.name} 默认图标保留旧Tooltip并隔离父级点击', (
        tester,
      ) async {
        var opens = 0;
        await _pumpStatus(
          tester,
          device: _android,
          language: language,
          brightness: brightness,
          isAirplayMirroring: true,
          showLabels: false,
          onTap: () => opens++,
        );
        final copy = AppLocalizations(Locale(language));
        for (final key in [
          'connectionUsb',
          'connectionTcp',
          'connectionWirelessDebug',
          'airplayServer',
        ]) {
          expect(find.byTooltip(copy.t(key)), findsOneWidget);
        }
        expect(
          find.byTooltip(copy.t('deviceWorkspaceUsbConnected')),
          findsNothing,
        );
        expect(find.byTooltip(copy.t('deviceWorkspaceAirplay')), findsNothing);
        for (final icon in [
          Icons.usb,
          CupertinoIcons.link,
          CupertinoIcons.wifi,
          Icons.airplay_rounded,
        ]) {
          final finder = find.byIcon(icon);
          expect(finder, findsOneWidget);
          expect(tester.widget<Icon>(finder).size, 16);
          await tester.tap(finder);
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(opens, 0);
        expect(find.byType(Text), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

/// 检查文字实际排版边界，避免只验证Widget存在而漏掉省略或横向裁剪。
void _expectCompleteLabel(WidgetTester tester, Finder label, Rect column) {
  final paragraph = tester.renderObject<RenderParagraph>(label);
  final text = tester.widget<Text>(label);
  final rect = tester.getRect(label);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  expect(rect.left, greaterThanOrEqualTo(column.left));
  expect(rect.right, lessThanOrEqualTo(column.right));
  expect(rect.bottom, lessThanOrEqualTo(column.bottom));
}

Future<void> _pumpStatus(
  WidgetTester tester, {
  required RegisteredDevice device,
  String language = 'zh',
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool isAirplayMirroring = false,
  bool showLabels = true,
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildAppTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: _columnKey,
            width: 80,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: DeviceConnectionIndicators(
                device: device,
                isAirplayMirroring: isAirplayMirroring,
                showLabels: showLabels,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
