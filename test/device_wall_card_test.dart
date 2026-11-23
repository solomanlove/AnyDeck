import 'dart:convert';
import 'dart:typed_data';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_asset_image.dart';
import 'package:any_deck/features/devices/widgets/device_tag_badge.dart';
import 'package:any_deck/features/devices/widgets/device_wall_card.dart';
import 'package:any_deck/features/devices/widgets/device_wall_phone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用真实 Theme 检查设备墙的尺寸、选择边界和截图真实性。
void main() {
  testWidgets('紧凑卡片保留手机比例、品牌身份和足够的操作点击区', (tester) async {
    var opens = 0;
    var infos = 0;
    var menus = 0;
    await tester.pumpWidget(
      _host(
        _card(
          previewOpensWorkspace: true,
          onOpen: () => opens++,
          onInfo: () => infos++,
          onMore: () => menus++,
        ),
      ),
    );

    final phone = find.byType(DeviceWallPhone);
    final size = tester.getSize(phone);
    expect(size.width, 120);
    expect(size.height, closeTo(120 * 18.5 / 9, .001));
    expect(tester.getSize(find.byType(DeviceWallCard)).height, lessThan(400));
    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      greaterThanOrEqualTo(40),
    );
    expect(tester.getSize(find.byType(IconButton)), const Size(40, 40));
    expect(
      tester
          .widgetList<AppAssetImage>(find.byType(AppAssetImage))
          .map((image) => image.assetName),
      [AppIcons.xiaomiSvg, AppIcons.xiaomiSvg],
    );
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.text('设备已就绪'), findsOneWidget);
    expect(find.text('当前屏幕快照'), findsOneWidget);
    expect(
      tester.widget<DeviceWallPhone>(phone).semanticLabel,
      '进入工作区 Mi MIX 3',
    );
    final mirror = find.widgetWithText(OutlinedButton, '投屏');
    expect(
      find.descendant(
        of: mirror,
        matching: find.byIcon(Icons.ondemand_video_outlined),
      ),
      findsOneWidget,
    );

    await tester.tap(phone);
    expect([opens, infos], [0, 1]);
    await tester.tap(mirror);
    expect([opens, infos], [1, 1]);
    await tester.tap(find.text('Mi MIX 3'));
    expect(infos, 2);
    await tester.tap(find.byType(IconButton));
    expect(menus, 1);
    expect(opens, 1);
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
            previewOpensWorkspace: true,
            onOpen: () => opens++,
            onInfo: () => fail('批量选择不能进入工作区'),
            onSelected: (value) => setState(() => selected = value),
          ),
        ),
      ),
    );
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(
      tester
          .widget<DeviceWallPhone>(find.byType(DeviceWallPhone))
          .semanticLabel,
      '选择设备 Mi MIX 3',
    );

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

  testWidgets('离线预览沿用重连操作，忙碌卡片拦截预览和主按钮', (tester) async {
    var reconnects = 0;
    final phone = find.byType(DeviceWallPhone);
    await tester.pumpWidget(
      _host(_card(online: false, onOpen: () => reconnects++)),
    );
    expect(
      tester.widget<DeviceWallPhone>(phone).semanticLabel,
      '重新连接 Mi MIX 3',
    );
    await tester.tap(phone);
    await tester.tap(find.widgetWithText(OutlinedButton, '重新连接'));
    expect(reconnects, 2);

    await tester.pumpWidget(
      _host(
        _card(
          busy: true,
          previewOpensWorkspace: true,
          onOpen: () => fail('忙碌时不能重复发起投屏'),
          onInfo: () => fail('忙碌时不能通过预览进入工作区'),
        ),
      ),
    );
    expect(tester.widget<DeviceWallPhone>(phone).onTap, isNull);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('在线仅显示传入的真实截图，离线不展示历史截图', (tester) async {
    final screenshot = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(_host(_card(screenshot: screenshot)));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(
      tester.widget<AppAssetImage>(find.byType(AppAssetImage)).assetName,
      AppIcons.xiaomiSvg,
      reason: '真实截图显示后，名称旁仍应保留品牌 Logo',
    );
    expect(find.text('设备已就绪'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _host(_card(online: false, screenshot: screenshot)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('设备未连接'), findsOneWidget);
    expect(find.text('通过 USB 或无线连接'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(DeviceWallPhone),
        matching: find.byWidgetPredicate(
          (widget) => widget is Positioned && widget.bottom == 21,
        ),
      ),
      findsNothing,
      reason: '离线封面应移除整个底部提示区域',
    );
    expect(
      find.descendant(
        of: find.byType(DeviceWallPhone),
        matching: find.byWidgetPredicate(
          (widget) => widget is Positioned && widget.bottom == 6,
        ),
      ),
      findsOneWidget,
      reason: '保留手机外观的底部手势条',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('封面复用既有手机品牌资源并支持型号兜底', (tester) async {
    final brands = {
      'Xiaomi': AppIcons.xiaomiSvg,
      'HONOR': AppIcons.honor,
      'Huawei': AppIcons.huawei,
      'Apple': AppIcons.apple,
      'Samsung': AppIcons.samsung,
      'HarmonyOS': AppIcons.huawei,
      'Android': AppIcons.xiaomiSvg,
    };
    for (final entry in brands.entries) {
      await tester.pumpWidget(
        _host(_card(brand: entry.key, name: 'Redmi K40')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<AppAssetImage>(find.byType(AppAssetImage))
            .map((image) => image.assetName),
        [entry.value, entry.value],
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('标签在名称下方居中展示，无标签和空白标签不预留空间', (tester) async {
    var opens = 0;
    var infos = 0;
    var selections = 0;
    await tester.pumpWidget(_host(_card()));
    final baseHeight = tester.getSize(find.byType(DeviceWallCard)).height;
    final phone = tester.getRect(find.byType(DeviceWallPhone));
    expect(find.byType(DeviceTagBadge), findsNothing);

    await tester.pumpWidget(_host(_card(tags: const ['', '  '])));
    expect(find.byType(DeviceTagBadge), findsNothing);
    expect(tester.getSize(find.byType(DeviceWallCard)).height, baseHeight);

    await tester.pumpWidget(
      _host(
        _card(
          tags: const ['主力机', 'Work'],
          onOpen: () => opens++,
          onInfo: () => infos++,
          onSelected: (_) => selections++,
        ),
      ),
    );
    expect(find.byType(DeviceTagBadge), findsNWidgets(2));
    final tags = find.ancestor(
      of: find.byType(DeviceTagBadge).first,
      matching: find.byType(Wrap),
    );
    expect(tester.widget<Wrap>(tags).alignment, WrapAlignment.center);
    expect(
      tester.getTopLeft(tags).dy,
      greaterThan(tester.getBottomLeft(find.text('Mi MIX 3')).dy),
    );
    expect(
      tester.getBottomLeft(tags).dy,
      lessThan(tester.getTopLeft(find.text('Android 15')).dy),
    );
    expect(tester.getRect(find.byType(DeviceWallPhone)), phone);
    await tester.tap(find.text('主力机'));
    expect([opens, infos, selections], [0, 0, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量模式点击标签只切换选择，禁选标签不触发任何设备动作', (tester) async {
    var selected = false;
    var opens = 0;
    var infos = 0;
    var menus = 0;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => _card(
            tags: const ['主力机'],
            batchMode: true,
            selected: selected,
            onSelected: (value) => setState(() => selected = value),
            onOpen: () => opens++,
            onInfo: () => infos++,
            onMore: () => menus++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('主力机'));
    await tester.pump();
    expect(selected, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect([opens, infos, menus], [0, 0, 0]);

    await tester.pumpWidget(
      _host(
        _card(
          tags: const ['主力机'],
          batchMode: true,
          selectable: false,
          onSelected: (_) => fail('禁选标签不得改变选择'),
          onOpen: () => opens++,
          onInfo: () => infos++,
          onMore: () => menus++,
        ),
      ),
    );
    await tester.tap(find.text('主力机'));
    expect([opens, infos, menus], [0, 0, 0]);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} 中英长名称在320px大字号设备墙中不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final language in ['zh', 'en']) {
        for (final batch in [false, true]) {
          await tester.pumpWidget(
            _host(
              _card(
                name: language == 'zh'
                    ? '荣耀 Magic V6 测试设备'
                    : 'sdk_gphone16k_arm64 Android Emulator',
                statusLabel: language == 'zh' ? 'USB 已连接' : 'USB connected',
                actionLabel: language == 'zh' ? '投屏' : 'Screen Mirror',
                tags: language == 'zh'
                    ? const ['主力机超长标签用于完整提示与省略验证', '测试机', '工作设备']
                    : const [
                        'Primary-device-for-long-label-tooltip',
                        'Testing',
                        'Work',
                      ],
                batchMode: batch,
              ),
              width: 146,
              brightness: brightness,
              textScale: 1.6,
              language: language,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final card = tester.getRect(find.byType(DeviceWallCard));
          final phone = tester.getRect(find.byType(DeviceWallPhone));
          expect(phone.left, greaterThanOrEqualTo(card.left));
          expect(phone.right, lessThanOrEqualTo(card.right));
          expect(find.byType(Checkbox), batch ? findsOneWidget : findsNothing);
          final badges = find.byType(DeviceTagBadge);
          expect(badges, findsNWidgets(3));
          final theme = Theme.of(tester.element(badges.first));
          final badgeContainer = tester.widget<Container>(
            find.descendant(of: badges.first, matching: find.byType(Container)),
          );
          final decoration = badgeContainer.decoration! as BoxDecoration;
          expect(
            decoration.color,
            theme.colorScheme.primaryContainer.withValues(alpha: .5),
          );
          expect(
            (decoration.border! as Border).top.color,
            theme.colorScheme.primary.withValues(alpha: .2),
          );
          final longTag = tester.widget<DeviceTagBadge>(badges.first).tag;
          expect(
            find.descendant(
              of: badges.first,
              matching: find.byTooltip(longTag),
            ),
            findsOneWidget,
          );
          final label = tester.widget<Text>(
            find.descendant(of: badges.first, matching: find.byType(Text)),
          );
          expect(label.maxLines, 1);
          expect(label.overflow, TextOverflow.ellipsis);
          for (final badge in badges.evaluate()) {
            final rect = tester.getRect(find.byWidget(badge.widget));
            expect(rect.left, greaterThanOrEqualTo(card.left));
            expect(rect.right, lessThanOrEqualTo(card.right));
          }
          expect(
            tester.getTopLeft(badges.last).dy,
            greaterThan(tester.getTopLeft(badges.first).dy),
          );
          if (!batch) {
            expect(
              tester.getSize(find.byType(OutlinedButton)).height,
              greaterThanOrEqualTo(40),
            );
            expect(tester.getSize(find.byType(IconButton)), const Size(40, 40));
          }
        }
      }
    });
  }
}

DeviceWallCard _card({
  String name = 'Mi MIX 3',
  String brand = 'Xiaomi',
  List<String> tags = const [],
  String statusLabel = 'USB 已连接',
  String? actionLabel,
  bool online = true,
  bool busy = false,
  bool previewOpensWorkspace = false,
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
  brand: brand,
  tags: tags,
  coverTitle: online ? '设备已就绪' : '设备未连接',
  coverHint: online ? '当前屏幕快照' : '通过 USB 或无线连接',
  actionLabel: actionLabel ?? (online ? '投屏' : '重新连接'),
  actionIcon: online ? Icons.ondemand_video_outlined : Icons.link,
  previewOpensWorkspace: previewOpensWorkspace,
  ipAddress: '192.168.1.219',
  online: online,
  busy: busy,
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
  String language = 'zh',
}) => MaterialApp(
  theme: buildAppTheme(brightness),
  locale: Locale(language),
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
