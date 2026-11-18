import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/ios/ios_connection_type.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/devices/model/device_list_presentation.dart';
import 'package:any_deck/features/devices/widgets/device_connection_indicators.dart';
import 'package:any_deck/features/devices/widgets/device_wall_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

const _statusRegionKey = Key('connection-status-region');
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

/// 检查横向连接状态的自然宽度、窄区域滚动及父级批量选择手势。
void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('设备墙 $language ${brightness.name} 使用短连接文案并保留完整说明', (
        tester,
      ) async {
        final devices = [
          _android.copyWith(model: 'Android test'),
          deviceMenuHarmony.copyWith(
            connections: ['harmony-device', '192.168.1.21:5555'],
          ),
          deviceMenuIos.copyWith(
            iosConnectionTypes: {
              IosConnectionType.usb,
              IosConnectionType.network,
            },
          ),
          deviceMenuOffline,
        ];
        await withDeviceMenu(
          tester,
          (fixture) async {
            final copy = AppLocalizations(Locale(language));
            for (final device in devices) {
              final card = find.byKey(ValueKey('device-wall-${device.id}'));
              expect(card, findsOneWidget);
              final channels = DeviceListPresentation.connections(device);
              if (channels.isEmpty) {
                expect(
                  tester.widget<DeviceWallCard>(card).statusLabel,
                  copy.t('deviceOffline'),
                );
                continue;
              }
              final short = channels
                  .map((channel) => copy.t(channel.shortLabelKey))
                  .join(' · ');
              final full = channels
                  .map((channel) => copy.t(channel.fullLabelKey))
                  .join(' · ');
              expect(tester.widget<DeviceWallCard>(card).statusLabel, short);
              expect(
                find.descendant(of: card, matching: find.text(short)),
                findsOneWidget,
              );
              expect(
                find.descendant(of: card, matching: find.text(full)),
                findsNothing,
              );
              expect(
                find.descendant(of: card, matching: find.byTooltip(full)),
                findsOneWidget,
              );
              expect(
                tester.getSemantics(card).getSemanticsData().label,
                startsWith('${device.displayName}，$full'),
              );
            }
            expect(
              find.text(copy.t('deviceWorkspaceUsbConnected')),
              findsNothing,
            );
            expect(fixture.adb.captures, isEmpty);
            expect(tester.takeException(), isNull);
          },
          devices: devices,
          language: language,
          brightness: brightness,
        );
      });
    }
  }

  // testWidgets 默认管理 SemanticsHandle，避免额外句柄晚于框架检查才释放。
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('$language ${brightness.name} $scale 倍字号全部连接横向单行展示', (
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
          final region = tester.getRect(find.byKey(_statusRegionKey));
          expect(region.width, greaterThanOrEqualTo(320));
          Rect? previousLabel;
          final centerY = tester.getCenter(find.text('USB')).dy;
          for (var i = 0; i < _androidLabels.length; i++) {
            final label = find.text(_androidLabels[i]);
            expect(label, findsOneWidget);
            expect(find.byTooltip(fullLabels[i]), findsOneWidget);
            _expectCompleteLabel(tester, label, region);
            final rect = tester.getRect(label);
            expect(rect.center.dy, closeTo(centerY, .1));
            if (previousLabel != null) {
              expect(rect.left, greaterThan(previousLabel.right));
            }
            previousLabel = rect;
            expect(tester.widget<Text>(label).maxLines, 1);
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
          final content = find.descendant(
            of: find.byType(DeviceConnectionIndicators),
            matching: find.byWidgetPredicate(
              (widget) => widget is Icon || widget is Text,
            ),
          );
          final tallest = content.evaluate().fold<double>(0, (height, element) {
            final size = tester.getSize(find.byWidget(element.widget));
            return size.height > height ? size.height : height;
          });
          expect(region.height, closeTo(tallest, .1));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('三通道自然宽度随内容计算且不增加单行高度', (tester) async {
    await _pumpStatus(tester, device: _android.copyWith(connections: ['usb']));
    final singleHeight = tester
        .getSize(find.byType(DeviceConnectionIndicators))
        .height;
    final singleWidth = _naturalWidth(
      tester,
      _android.copyWith(connections: ['usb']),
    );
    await _pumpStatus(tester, device: _android);
    final fullWidth = _naturalWidth(tester, _android);
    final labels = [
      for (final key in _androidFullKeys.take(3))
        tester.getRect(
          find.byTooltip(AppLocalizations(const Locale('zh')).t(key)),
        ),
    ];
    expect(fullWidth, greaterThan(singleWidth));
    final drawnWidth = labels.last.right - labels.first.left;
    // 测量结果可包含逐标签向上取整和尾部安全像素，不能预留空通道宽度。
    expect(fullWidth - drawnWidth, inInclusiveRange(0, labels.length + 2));
    for (var index = 1; index < labels.length; index++) {
      expect(labels[index].left - labels[index - 1].right, closeTo(6, .1));
      expect(labels[index].center.dy, closeTo(labels.first.center.dy, .1));
    }
    final fullHeight = tester
        .getSize(find.byType(DeviceConnectionIndicators))
        .height;
    expect(fullHeight, singleHeight);
    expect(fullHeight, lessThan(20));
    expect(tester.takeException(), isNull);
  });

  for (final airplay in [false, true]) {
    testWidgets('80px区域横向滚动到${airplay ? 'AirPlay' : 'Wi-Fi'}后仍可选择设备', (
      tester,
    ) async {
      var selections = 0;
      await _pumpStatus(
        tester,
        device: _android,
        width: 80,
        isAirplayMirroring: airplay,
        onTap: () => selections++,
      );
      final region = tester.getRect(find.byKey(_statusRegionKey));
      final last = find.text(airplay ? 'AirPlay' : 'Wi-Fi');
      final first = find.text('USB');
      expect(tester.getRect(last).left, greaterThan(region.right));
      final centerY = tester.getCenter(first).dy;
      expect(tester.getCenter(last).dy, closeTo(centerY, .1));
      await tester.tap(first);
      await tester.pump();
      expect(selections, 1);
      final scrollable = find.descendant(
        of: find.byType(DeviceConnectionIndicators),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      expect(
        tester.state<ScrollableState>(scrollable).position.axis,
        Axis.horizontal,
      );
      await tester.drag(scrollable, const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(selections, 1);
      _expectCompleteLabel(tester, last, region);
      expect(tester.getCenter(last).dy, closeTo(centerY, .1));
      await tester.tap(last);
      await tester.pump();
      expect(selections, 2);
      final copy = AppLocalizations(const Locale('zh'));
      final fullKeys = airplay ? _androidFullKeys : _androidFullKeys.take(3);
      expect(
        find.bySemanticsLabel(fullKeys.map(copy.t).join(', ')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
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
          width: 80,
          textScale: 1.6,
          onTap: () => selections++,
        );
        final label = find.text(copy.t(labelKey));
        expect(label, findsOneWidget);
        expect(find.bySemanticsLabel(copy.t(labelKey)), findsOneWidget);
        _expectCompleteLabel(
          tester,
          label,
          tester.getRect(find.byKey(_statusRegionKey)),
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
void _expectCompleteLabel(WidgetTester tester, Finder label, Rect region) {
  final paragraph = tester.renderObject<RenderParagraph>(label);
  final text = tester.widget<Text>(label);
  final rect = tester.getRect(label);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  expect(rect.left, greaterThanOrEqualTo(region.left - .1));
  expect(rect.right, lessThanOrEqualTo(region.right + .1));
  expect(rect.bottom, lessThanOrEqualTo(region.bottom + .1));
}

double _naturalWidth(WidgetTester tester, RegisteredDevice device) =>
    DeviceConnectionIndicators.labelsWidth(
      tester.element(find.byType(DeviceConnectionIndicators)),
      DeviceListPresentation.connections(device),
    );

Future<void> _pumpStatus(
  WidgetTester tester, {
  required RegisteredDevice device,
  String language = 'zh',
  Brightness brightness = Brightness.light,
  double textScale = 1,
  double? width,
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
        body: Builder(
          builder: (context) {
            final channels = DeviceListPresentation.connections(
              device,
              isAirplayMirroring: isAirplayMirroring,
            );
            final naturalWidth = showLabels && channels.isNotEmpty
                ? DeviceConnectionIndicators.labelsWidth(context, channels)
                : 80.0;
            final regionWidth =
                width ?? (naturalWidth > 320 ? naturalWidth : 320.0);
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                key: _statusRegionKey,
                width: regionWidth,
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
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
