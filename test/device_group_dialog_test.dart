import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/device_groups/device_groups_controller.dart';
import 'package:any_deck/core/device_groups/device_groups_store.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/devices/widgets/device_group_filter.dart';
import 'package:any_deck/features/devices/widgets/device_groups_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = RegisteredDevice(
  id: 'dialog-usb',
  serial: 'dialog-physical',
  model: 'Test Phone',
  status: 'device',
  isOnline: true,
);

/// 在真实 Widget 上控制存储失败；测试不访问 SharedPreferences 或设备服务。
class _DialogStore extends DeviceGroupsStore {
  _DialogStore()
    : saved = DeviceGroupsState(
        customGroups: [
          DeviceGroup(
            id: 'qa',
            name: 'QA',
            members: [DeviceGroupMember.fromDevice(_phone)],
          ),
        ],
      );

  DeviceGroupsState saved;
  int loadFailures = 0;
  int loads = 0;
  int saves = 0;
  bool saveFails = false;

  @override
  Future<DeviceGroupsState> load() async {
    loads++;
    if (loadFailures > 0) {
      loadFailures--;
      throw StateError('temporarily unavailable');
    }
    return saved;
  }

  @override
  Future<void> save(DeviceGroupsState value) async {
    saves++;
    if (saveFails) throw StateError('disk unavailable');
    saved = value;
  }
}

void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('分组浮动标签完整显示 $language ${brightness.name} $scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          for (final width in [320.0, 900.0]) {
            tester.view.physicalSize = Size(width, 900);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(
              _host(
                store: _DialogStore(),
                language: language,
                brightness: brightness,
                scale: scale,
                devices: [
                  for (var i = 0; i < 20; i++) _phone.copyWith(id: 'phone-$i'),
                ],
              ),
            );
            await tester.pumpAndSettle();
            await _openManager(tester);
            _expectGroupLabelVisible(tester, language);
            await tester.tap(
              find.byKey(const ValueKey('deviceGroupEditor-qa')),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Android').last);
            await tester.pumpAndSettle();
            _expectGroupLabelVisible(tester, language);
            await tester.tap(
              find.byKey(const ValueKey('deviceGroupEditor-android')),
            );
            await tester.pumpAndSettle();
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            _expectGroupLabelVisible(tester, language);
            final scroll = tester.state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(DeviceGroupsDialog),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            scroll.position.jumpTo(scroll.position.maxScrollExtent);
            await tester.pumpAndSettle();
            scroll.position.jumpTo(scroll.position.minScrollExtent);
            await tester.pumpAndSettle();
            _expectGroupLabelVisible(tester, language);
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }

  testWidgets('加载失败保留默认平台筛选，重试恢复旧组且不写盘', (tester) async {
    final store = _DialogStore()..loadFailures = 1;
    final selected = <String?>[];
    await tester.pumpWidget(_host(store: store, onChanged: selected.add));
    await tester.pumpAndSettle();
    await _openFilter(tester);
    for (final platform in ['android', 'harmony', 'ios']) {
      expect(find.byKey(Key('deviceGroupOption-$platform')), findsOneWidget);
    }
    expect(find.byKey(const Key('deviceGroupManage')), findsNothing);
    expect(find.byKey(const Key('deviceGroupRetry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('deviceGroupOption-android')));
    await tester.pumpAndSettle();
    expect(selected, ['android']);
    expect(store.saves, 0);

    await _openFilter(tester);
    await tester.tap(find.byKey(const Key('deviceGroupRetry')));
    await tester.pumpAndSettle();
    await _openFilter(tester);
    expect(find.byKey(const Key('deviceGroupOption-qa')), findsOneWidget);
    expect(find.byKey(const Key('deviceGroupManage')), findsOneWidget);
    expect(find.byKey(const Key('deviceGroupRetry')), findsNothing);
    expect(store.loads, 2);
    expect(store.saves, 0);
    expect(store.saved.matches('qa', _phone), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['zh', 'en']) {
    testWidgets('成员保存失败显示 $language 错误，保留旧勾选并可重试', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 900);
      addTearDown(tester.view.reset);
      final store = _DialogStore()..saveFails = true;
      final devices = [
        for (var index = 0; index < 20; index++)
          RegisteredDevice(
            id: 'other-$index',
            serial: 'other-physical-$index',
            model: 'Other Phone $index',
            status: 'device',
            isOnline: true,
          ),
        _phone,
      ];
      await tester.pumpWidget(
        _host(store: store, language: language, scale: 1.6, devices: devices),
      );
      await tester.pumpAndSettle();
      await _openManager(tester);
      final member = await _revealDialogControl(
        tester,
        'deviceGroupMember-dialog-usb',
      );
      expect(tester.widget<CheckboxListTile>(member).value, isTrue);
      await tester.tap(member);
      await tester.pumpAndSettle();
      expect(
        find
            .text(
              language == 'zh'
                  ? '分组保存失败，请重试'
                  : 'Could not save groups. Please try again.',
            )
            .hitTestable(),
        findsOneWidget,
      );
      await _revealDialogControl(tester, 'deviceGroupMember-dialog-usb');
      expect(tester.widget<CheckboxListTile>(member).value, isTrue);
      expect(store.saved.matches('qa', _phone), isTrue);
      store.saveFails = false;
      await _tapDialogControl(tester, 'deviceGroupMember-dialog-usb');
      await _revealDialogControl(tester, 'deviceGroupMember-dialog-usb');
      expect(tester.widget<CheckboxListTile>(member).value, isFalse);
      expect(store.saved.matches('qa', _phone), isFalse);
      expect(store.saves, 2);
      expect(tester.takeException(), isNull);
    });

    for (final brightness in Brightness.values) {
      testWidgets('窄屏分组管理 $language ${brightness.name} 大字号操作无溢出', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final width in [320.0, 360.0]) {
          tester.view.physicalSize = Size(width, 900);
          // 重建 Scope，确保每种宽度独立验证真实创建和重命名流程。
          await tester.pumpWidget(const SizedBox.shrink());
          final store = _DialogStore();
          await tester.pumpWidget(
            _host(
              store: store,
              language: language,
              brightness: brightness,
              scale: 1.6,
            ),
          );
          await tester.pumpAndSettle();
          await _openManager(tester);
          expect(find.byType(DeviceGroupsDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _tapDialogControl(tester, 'deviceGroupCreate');
          await tester.enterText(
            find.byKey(const Key('deviceGroupNameInput')),
            'Small QA',
          );
          await tester.tap(find.byKey(const Key('deviceGroupNameSave')));
          await tester.pumpAndSettle();
          expect(store.saved.customGroups, hasLength(2));
          expect(tester.takeException(), isNull);
          await _tapDialogControl(tester, 'deviceGroupRename');
          await tester.enterText(
            find.byKey(const Key('deviceGroupNameInput')),
            'Team phones',
          );
          await tester.tap(find.byKey(const Key('deviceGroupNameSave')));
          await tester.pumpAndSettle();
          expect(store.saved.customGroups.last.name, 'Team phones');
          expect(tester.takeException(), isNull);
          await _tapDialogControl(tester, 'deviceGroupMember-dialog-usb');
          expect(store.saved.customGroups.last.matches(_phone), isTrue);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(language == 'zh' ? '关闭' : 'Close'));
          await tester.pumpAndSettle();
          expect(find.byType(DeviceGroupsDialog), findsNothing);
        }
      });
    }
  }
}

/// 使用实际 Paint Transform 检查浮动标签，避免“存在 Text”掩盖裁切。
void _expectGroupLabelVisible(WidgetTester tester, String language) {
  final dialog = find.byType(DeviceGroupsDialog);
  final label = tester.renderObject<RenderBox>(
    find.descendant(
      of: dialog,
      matching: find.text(
        AppLocalizations(Locale(language)).t('deviceGroupFilter'),
      ),
    ),
  );
  final viewport = tester.renderObject<RenderBox>(
    find.descendant(of: dialog, matching: find.byType(Viewport)),
  );
  final painted = MatrixUtils.transformRect(
    label.getTransformTo(viewport),
    Offset.zero & label.size,
  );
  expect(painted.top, greaterThanOrEqualTo(0), reason: '浮动标签不应被滚动区域顶部裁切');
  expect(painted.bottom, lessThanOrEqualTo(viewport.size.height));
}

/// 成员由 SliverList 惰性创建；先滚动生成，再执行真实点击。
Future<Finder> _revealDialogControl(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      100,
      scrollable: find
          .descendant(
            of: find.byType(DeviceGroupsDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pumpAndSettle();
  return target;
}

Future<void> _tapDialogControl(WidgetTester tester, String key) async {
  await tester.tap(await _revealDialogControl(tester, key));
  await tester.pumpAndSettle();
}

Future<void> _openFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('deviceGroupFilter')));
  await tester.pumpAndSettle();
}

Future<void> _openManager(WidgetTester tester) async {
  await _openFilter(tester);
  final manage = find.byKey(const Key('deviceGroupManage'));
  await tester.ensureVisible(manage);
  await tester.tap(manage);
  await tester.pumpAndSettle();
}

Widget _host({
  required _DialogStore store,
  ValueChanged<String?>? onChanged,
  String language = 'zh',
  Brightness brightness = Brightness.light,
  double scale = 1,
  List<RegisteredDevice> devices = const [_phone],
}) => ProviderScope(
  overrides: [deviceGroupsStoreProvider.overrideWithValue(store)],
  child: MaterialApp(
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
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: content!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 144 * scale,
          child: DeviceGroupFilter(
            selectedGroupId: 'qa',
            onChanged: onChanged ?? (_) {},
            devices: devices,
            names: const {'dialog-usb': 'Test Phone'},
          ),
        ),
      ),
    ),
  ),
);
