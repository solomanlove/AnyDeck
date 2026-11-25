import 'dart:ui' as ui;

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/device_groups/device_groups_controller.dart';
import 'package:any_deck/core/device_groups/device_groups_store.dart';
import 'package:any_deck/features/devices/widgets/device_connection_menu.dart';
import 'package:any_deck/features/devices/widgets/device_group_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _groupButton = Key('deviceGroupFilter');
const _menuCanvas = Key('deviceGroupMenuTestCanvas');
const _customName = '用于验证窄窗口内超长名称显示的自定义设备分组';

/// 使用固定分组快照，验证菜单时不访问磁盘或设备服务。
class _MenuStore extends DeviceGroupsStore {
  int saves = 0;

  @override
  Future<DeviceGroupsState> load() async => DeviceGroupsState(
    customGroups: [DeviceGroup(id: 'qa', name: _customName)],
  );

  @override
  Future<void> save(DeviceGroupsState value) async => saves++;
}

/// 比较真实菜单的外观与交互，不依赖共享样式组件的内部实现。
void main() {
  for (final brightness in Brightness.values) {
    testWidgets('分组水波纹铺满整行并按菜单外框裁切 ${brightness.name}', (tester) async {
      await _pumpMenus(
        tester,
        language: 'zh',
        brightness: brightness,
        store: _MenuStore(),
        onChanged: (_) {},
      );
      await _openGroup(tester);
      final first = tester.getRect(_entry(''));
      final last = tester.getRect(find.byKey(const Key('deviceGroupManage')));
      final menu = tester.getRect(_surface(_entry('')));
      final samples = [
        menu.topLeft + const Offset(1, 1),
        menu.topCenter + const Offset(0, 2),
        Offset(menu.left + 2, first.bottom - 2),
        Offset(menu.left + 2, first.bottom + 2),
        Offset(menu.left + 2, last.top + 2),
        menu.bottomCenter - const Offset(0, 2),
        menu.bottomLeft + const Offset(1, -2),
      ];

      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(4, 4));
      addTearDown(mouse.removePointer);
      await tester.pumpAndSettle();
      final idle = await _menuPixels(tester, samples);

      await mouse.moveTo(first.center);
      await tester.pumpAndSettle();
      final firstHover = await _menuPixels(tester, samples);
      expect(firstHover[0], idle[0], reason: '首项的顶部外角由菜单圆角裁切');
      expect(firstHover[1], isNot(idle[1]), reason: '首项高亮铺到菜单上沿');
      expect(firstHover[2], isNot(idle[2]), reason: '首项底角直切并铺到菜单左沿');
      expect(firstHover[3], idle[3], reason: '高亮止于当前菜单项');

      await mouse.moveTo(last.center);
      await tester.pumpAndSettle();
      final lastHover = await _menuPixels(tester, samples);
      expect(lastHover[4], isNot(idle[4]), reason: '末项顶角直切并铺到菜单左沿');
      expect(lastHover[5], isNot(idle[5]), reason: '末项高亮铺到菜单下沿');
      expect(lastHover[6], idle[6], reason: '末项的底部外角由菜单圆角裁切');

      await mouse.moveTo(const Offset(4, 4));
      await tester.pumpAndSettle();
      final touch = await tester.startGesture(first.center);
      try {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        final pressed = await _menuPixels(tester, samples);
        expect(pressed[0], idle[0], reason: '按压水波纹同样受外框圆角裁切');
        expect(pressed[1], isNot(idle[1]), reason: '按压水波纹铺到菜单上沿');
        expect(pressed[2], isNot(idle[2]), reason: '按压水波纹铺到首项底角');
      } finally {
        await touch.cancel();
      }
    });
  }

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('窄窗口分组浮窗与全宽入口两侧对齐 $language ${brightness.name}', (
        tester,
      ) async {
        await _pumpMenus(
          tester,
          language: language,
          brightness: brightness,
          store: _MenuStore(),
          onChanged: (_) {},
          width: 320,
        );
        await tester.tap(find.byKey(const Key('deviceConnectionButton')));
        await tester.pumpAndSettle();
        final connection = tester.getRect(
          _surface(find.byKey(const Key('deviceConnection-pair'))),
        );
        expect(connection.width, closeTo(240, .1));
        await _escape(tester);

        final button = tester.getRect(find.byKey(_groupButton));
        final folder = find.descendant(
          of: find.byKey(_groupButton),
          matching: find.byIcon(Icons.folder_open_outlined),
        );
        expect(folder, findsOneWidget);
        expect(
          IconTheme.of(tester.element(folder)).color,
          Theme.of(tester.element(folder)).colorScheme.onSurface,
        );
        await _openGroup(tester);
        final menu = tester.getRect(_surface(_entry('android')));
        _expectMenuAlignment(menu, button);
        expect(menu.left, greaterThanOrEqualTo(0));
        expect(menu.right, lessThanOrEqualTo(320));
        for (final item in [
          _entry(''),
          _entry('android'),
          _entry('harmony'),
          _entry('ios'),
          find.byKey(const Key('deviceGroupManage')),
        ]) {
          final text = find.descendant(of: item, matching: find.byType(Text));
          expect(
            tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
            isFalse,
          );
          expect(tester.getRect(text).right, lessThanOrEqualTo(menu.right));
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('分组菜单复用连接背景和平台图标 $language ${brightness.name}', (
        tester,
      ) async {
        final selected = <String?>[];
        final store = _MenuStore();
        await _pumpMenus(
          tester,
          language: language,
          brightness: brightness,
          store: store,
          onChanged: selected.add,
        );
        await tester.tap(find.byKey(const Key('deviceConnectionButton')));
        await tester.pumpAndSettle();
        final connection = tester.widget<Material>(
          _surface(find.byKey(const Key('deviceConnection-pair'))),
        );
        await _escape(tester);

        final button = tester.getRect(find.byKey(_groupButton));
        await _openGroup(tester);
        final surface = _surface(_entry('android'));
        final material = tester.widget<Material>(surface);
        final theme = Theme.of(tester.element(surface));
        expect(material.color, connection.color);
        expect(material.color, theme.appColors.panelSurface);
        expect(material.surfaceTintColor, Colors.transparent);
        expect(material.surfaceTintColor, connection.surfaceTintColor);
        expect(material.elevation, connection.elevation);
        expect(material.shape, connection.shape);
        expect(material.shadowColor, connection.shadowColor);
        final menu = tester.getRect(surface);
        expect(menu.top, greaterThanOrEqualTo(button.bottom));
        _expectMenuAlignment(menu, button);
        expect(menu.left, greaterThanOrEqualTo(0));
        expect(menu.right, lessThanOrEqualTo(900));

        _expectPlatformIcons(tester);
        final entries = [
          _entry(''),
          _entry('android'),
          _entry('harmony'),
          _entry('ios'),
          _entry('qa'),
          find.byKey(const Key('deviceGroupManage')),
        ];
        final textLeft = entries
            .map(
              (item) => tester
                  .getTopLeft(
                    find.descendant(of: item, matching: find.byType(Text)),
                  )
                  .dx,
            )
            .toList();
        expect(textLeft, everyElement(closeTo(textLeft.first, .1)));
        expect(
          find.descendant(
            of: _entry('qa'),
            matching: find.byIcon(Icons.folder_outlined),
          ),
          findsOneWidget,
        );
        expect(
          find.text(language == 'zh' ? '管理分组' : 'Manage groups'),
          findsOneWidget,
        );
        _expectCheck('');
        expect(
          tester.widget<Icon>(find.byIcon(Icons.check)).color,
          theme.colorScheme.onSurface,
        );

        // 选择仅改变当前过滤条件；再次打开时勾选应跟随宿主状态。
        for (final id in ['android', 'harmony', 'ios', 'qa', '']) {
          final option = _entry(id);
          final optionIcon = _groupIconIn(option, id);
          final optionSize = tester.getSize(optionIcon);
          final optionGap = _iconLabelGap(tester, option, optionIcon);
          await tester.tap(option);
          await tester.pumpAndSettle();
          expect(_entry('android'), findsNothing);
          expect(selected.last, id.isEmpty ? null : id);
          final trigger = find.byKey(_groupButton);
          final triggerIcon = _groupIconIn(trigger, id);
          expect(triggerIcon, findsOneWidget);
          expect(tester.getSize(triggerIcon), optionSize);
          expect(
            _iconLabelGap(tester, trigger, triggerIcon),
            closeTo(optionGap, .1),
          );
          if (id == 'harmony') {
            expect(
              tester.widget<Image>(triggerIcon).image,
              const AssetImage(AppIcons.huaweiPetal),
            );
          }
          await _openGroup(tester);
          _expectCheck(id);
        }
        expect(selected, ['android', 'harmony', 'ios', 'qa', null]);
        await _escape(tester);
        await _openGroup(tester);
        await tester.tapAt(const Offset(20, 600));
        await tester.pumpAndSettle();
        expect(_entry('android'), findsNothing);
        expect(selected, hasLength(5));
        expect(store.saves, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('320px大字号分组菜单可读且长名称不溢出 $language ${brightness.name}', (
        tester,
      ) async {
        final selected = <String?>[];
        await _pumpMenus(
          tester,
          language: language,
          brightness: brightness,
          store: _MenuStore(),
          onChanged: selected.add,
          width: 320,
          scale: 1.6,
        );
        final button = tester.getRect(find.byKey(_groupButton));
        await _openGroup(tester);
        final menu = tester.getRect(_surface(_entry('android')));
        _expectMenuAlignment(menu, button);
        expect(menu.left, greaterThanOrEqualTo(0));
        expect(menu.right, lessThanOrEqualTo(320));
        expect(menu.bottom, lessThanOrEqualTo(700));
        for (final item in [
          _entry(''),
          _entry('android'),
          _entry('harmony'),
          _entry('ios'),
          find.byKey(const Key('deviceGroupManage')),
        ]) {
          final text = find.descendant(of: item, matching: find.byType(Text));
          expect(
            tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
            isFalse,
          );
          final rect = tester.getRect(text);
          expect(rect.left, greaterThanOrEqualTo(menu.left));
          expect(rect.right, lessThanOrEqualTo(menu.right));
          expect(rect.bottom, lessThanOrEqualTo(menu.bottom));
        }
        final custom = find.descendant(
          of: _entry('qa'),
          matching: find.text(_customName),
        );
        final label = tester.widget<Text>(custom);
        expect(label.maxLines, 1);
        expect(label.overflow, TextOverflow.ellipsis);
        expect(tester.getRect(custom).right, lessThanOrEqualTo(menu.right));
        _expectPlatformIcons(tester);
        await tester.tap(_entry('qa'));
        await tester.pumpAndSettle();
        expect(selected, ['qa']);
        expect(_entry('android'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

/// 检查 Material 交互高亮实际绘制的位置，保留边框和抗锯齿。
Future<List<int>> _menuPixels(WidgetTester tester, List<Offset> points) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_menuCanvas),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return [
        for (final point in points.map(boundary.globalToLocal))
          bytes.getUint32(
            (point.dy.floor() * image.width + point.dx.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

Finder _entry(String id) => id.isEmpty
    ? find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == '',
      )
    : find.byKey(ValueKey('deviceGroupOption-$id'));

Finder _groupIconIn(Finder parent, String id) => find.descendant(
  of: parent,
  matching: switch (id) {
    'android' => find.byIcon(Icons.android_rounded),
    'harmony' => find.byType(Image),
    'ios' => find.byIcon(Icons.apple),
    '' => find.byIcon(Icons.folder_open_outlined),
    _ => find.byIcon(Icons.folder_outlined),
  },
);

/// 用渲染后的位置比较按钮和菜单项的图标与文字间距。
double _iconLabelGap(WidgetTester tester, Finder parent, Finder icon) =>
    tester
        .getRect(find.descendant(of: parent, matching: find.byType(Text)))
        .left -
    tester.getRect(icon).right;

Finder _surface(Finder item) =>
    find.ancestor(of: item, matching: find.byType(Material)).first;

/// 校验可见菜单表面和按钮实际矩形，避免只比较固定尺寸。
void _expectMenuAlignment(Rect menu, Rect button) {
  expect(menu.width, closeTo(button.width, .1));
  expect(menu.left, closeTo(button.left, .1));
  expect(menu.right, closeTo(button.right, .1));
}

Future<void> _openGroup(WidgetTester tester) async {
  await tester.tap(find.byKey(_groupButton));
  await tester.pumpAndSettle();
  expect(_entry('android'), findsOneWidget);
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.byType(PopupMenuItem<String>), findsNothing);
}

void _expectCheck(String id) {
  expect(find.byIcon(Icons.check), findsOneWidget);
  expect(
    find.descendant(of: _entry(id), matching: find.byIcon(Icons.check)),
    findsOneWidget,
  );
}

void _expectPlatformIcons(WidgetTester tester) {
  expect(
    find.descendant(
      of: _entry('android'),
      matching: find.byIcon(Icons.android_rounded),
    ),
    findsOneWidget,
  );
  final huawei = find.descendant(
    of: _entry('harmony'),
    matching: find.byType(Image),
  );
  expect(
    tester.widget<Image>(huawei).image,
    const AssetImage(AppIcons.huaweiPetal),
  );
  final apple = find.descendant(
    of: _entry('ios'),
    matching: find.byIcon(Icons.apple),
  );
  expect(apple, findsOneWidget);
  expect(
    tester.widget<Icon>(apple).color,
    Theme.of(tester.element(apple)).colorScheme.onSurface,
  );
  for (final id in ['android', 'harmony', 'ios']) {
    final item = _entry(id);
    final icon = find.descendant(
      of: item,
      matching: id == 'harmony'
          ? find.byType(Image)
          : find.byIcon(id == 'android' ? Icons.android_rounded : Icons.apple),
    );
    final text = find.descendant(of: item, matching: find.byType(Text));
    expect(tester.getRect(icon).right, lessThan(tester.getRect(text).left));
  }
}

Future<void> _pumpMenus(
  WidgetTester tester, {
  required String language,
  required Brightness brightness,
  required _MenuStore store,
  required ValueChanged<String?> onChanged,
  double width = 900,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  String? groupId;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [deviceGroupsStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        theme: buildDeviceWorkspaceTheme(buildAppTheme(brightness)),
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: _menuCanvas, child: child!),
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    DeviceConnectionMenu(
                      onSelected: (_) {},
                      showLabel: width > 320,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: width <= 320 ? 288 : 144,
                      child: DeviceGroupFilter(
                        selectedGroupId: groupId,
                        onChanged: (value) {
                          update(() => groupId = value);
                          onChanged(value);
                        },
                        devices: const [],
                        names: const {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
