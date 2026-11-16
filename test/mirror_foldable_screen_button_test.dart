import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/app/window/mirror/mirror_floating_toolbar.dart';
import 'package:any_deck/app/window/mirror/mirror_window_controller.dart';
import 'package:any_deck/app/window/mirror/widget/mirror_foldable_screen_button.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/device_actions/device_action_service.dart';
import 'package:any_deck/core/foldable/foldable_screen_controller.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _button = ValueKey('mirror-foldable-screen-toggle');
const _innerIcon = ValueKey('mirror-foldable-inner-icon');
const _outerIcon = ValueKey('mirror-foldable-outer-icon');
const _automaticBadge = ValueKey('mirror-foldable-automatic-badge');

const _capability = FoldableScreenCapability(
  innerStateId: 3,
  outerStateId: 0,
  innerPhysicalId: '111',
  outerPhysicalId: '222',
);
const _innerSnapshot = FoldableScreenSnapshot(
  capability: _capability,
  currentScreen: FoldableScreen.inner,
  committedStateId: 3,
  hasOverride: false,
);
const _outerSnapshot = FoldableScreenSnapshot(
  capability: _capability,
  currentScreen: FoldableScreen.outer,
  committedStateId: 0,
  hasOverride: true,
);
const _unknownSnapshot = FoldableScreenSnapshot(
  capability: _capability,
  currentScreen: null,
  committedStateId: 8,
  hasOverride: false,
);

/// 隔离真实 ADB 和清理逻辑，仅控制 UI 收到的状态及异步结果。
class _Controller extends FoldableScreenController {
  _Controller(this.initial) : super('phone');

  final FoldableScreenUiState initial;
  int builds = 0;
  int toggles = 0;
  int restores = 0;
  FoldableScreenError? nextError;
  Completer<FoldableScreenError?>? pending;

  @override
  FoldableScreenUiState build() {
    builds++;
    return initial;
  }

  void update(FoldableScreenUiState value) => state = value;

  @override
  Future<FoldableScreenError?> toggle() async {
    toggles++;
    return pending == null ? nextError : pending!.future;
  }

  @override
  Future<FoldableScreenError?> restoreAutomatic() async {
    restores++;
    return nextError;
  }
}

Future<void> _pumpButton(
  WidgetTester tester,
  _Controller controller, {
  String language = 'zh',
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        foldableScreenProvider('phone').overrideWith(() => controller),
      ],
      child: MaterialApp(
        theme: buildAppTheme(brightness),
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: const Scaffold(
          body: Center(child: MirrorFoldableScreenButton(deviceId: 'phone')),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _tooltip(WidgetTester tester) =>
    tester.widget<MirrorToolbarButton>(find.byKey(_button)).tooltip;

/// 挂载真实工具栏，控制器不启动投屏；只替换设备命令门面以隔离系统进程。
Future<void> _pumpToolbar(
  WidgetTester tester,
  _Controller foldable, {
  bool isHarmony = false,
  bool isAppMirror = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        foldableScreenProvider('phone').overrideWith(() => foldable),
        deviceActionServiceProvider.overrideWithValue(
          DeviceActionService(AdbService(executable: 'adb')),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, child) => MirrorFloatingToolbar(
              deviceId: 'phone',
              deviceName: 'AnyDeck test',
              windowId: 'test',
              controller: MirrorWindowController(
                ref: ref,
                deviceId: 'phone',
                windowId: 'test',
                isHarmony: isHarmony,
                startApp: isAppMirror ? 'com.example.app' : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(AppToast.dismiss);

  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('自动与手动的图标、提示和主题 $brightness $language', (tester) async {
        final controller = _Controller(
          const FoldableScreenUiState(snapshot: _innerSnapshot),
        );
        await _pumpButton(
          tester,
          controller,
          language: language,
          brightness: brightness,
        );
        expect(find.byKey(_innerIcon), findsOneWidget);
        expect(find.byKey(_outerIcon), findsNothing);
        expect(find.byKey(_automaticBadge), findsOneWidget);
        expect(
          _tooltip(tester),
          language == 'zh'
              ? '自动切屏 · 当前内屏\n点击切换到外屏；长按恢复自动'
              : 'Automatic · Current: inner screen\nClick to use the outer screen; hold to restore automatic switching',
        );
        final context = tester.element(find.byKey(_button));
        expect(
          tester.widget<Icon>(find.byKey(_innerIcon)).color,
          Theme.of(context).appColors.toolbarForeground,
        );

        controller.update(
          const FoldableScreenUiState(
            snapshot: _outerSnapshot,
            mode: FoldableScreenMode.outer,
          ),
        );
        await tester.pump();
        expect(find.byKey(_innerIcon), findsNothing);
        expect(find.byKey(_outerIcon), findsOneWidget);
        expect(find.byKey(_automaticBadge), findsNothing);
        expect(
          _tooltip(tester),
          language == 'zh'
              ? '手动切屏 · 当前外屏\n点击切换到内屏；长按恢复自动'
              : 'Manual · Current: outer screen\nClick to use the inner screen; hold to restore automatic switching',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('未支持或当前屏幕未确认时隐藏按钮', (tester) async {
    final controller = _Controller(const FoldableScreenUiState());
    await _pumpButton(tester, controller);
    expect(find.byKey(_button), findsNothing);
    controller.update(const FoldableScreenUiState(snapshot: _unknownSnapshot));
    await tester.pump();
    expect(find.byKey(_button), findsNothing);
  });

  testWidgets('其他工具的覆盖状态不显示自动角标', (tester) async {
    final controller = _Controller(
      const FoldableScreenUiState(snapshot: _outerSnapshot),
    );
    await _pumpButton(tester, controller);
    expect(find.byKey(_outerIcon), findsOneWidget);
    expect(find.byKey(_automaticBadge), findsNothing);
    expect(_tooltip(tester), startsWith('手动切屏 · 当前外屏'));
  });

  testWidgets('切换中显示加载并阻止点击和长按', (tester) async {
    final controller = _Controller(
      const FoldableScreenUiState(snapshot: _innerSnapshot, isBusy: true),
    );
    await _pumpButton(tester, controller);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_tooltip(tester), '正在切换屏幕…');
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
    await tester.tap(find.byKey(_button));
    await tester.longPress(find.byKey(_button));
    expect(controller.toggles, 0);
    expect(controller.restores, 0);
  });

  testWidgets('点击发起切换，长按恢复自动并反馈成功', (tester) async {
    final controller = _Controller(
      const FoldableScreenUiState(
        snapshot: _innerSnapshot,
        mode: FoldableScreenMode.inner,
      ),
    );
    await _pumpButton(tester, controller);
    await tester.tap(find.byKey(_button));
    await tester.pump();
    expect(controller.toggles, 1);
    expect(controller.restores, 0);
    await tester.longPress(find.byKey(_button));
    await tester.pump();
    expect(controller.toggles, 1);
    expect(controller.restores, 1);
    expect(find.text('已恢复自动切屏'), findsOneWidget);
    AppToast.dismiss();
    await tester.pump();
  });

  const errors = {
    FoldableScreenError.unsupported: '当前设备暂不支持内外屏切换',
    FoldableScreenError.unavailable: '当前设备暂不支持内外屏切换',
    FoldableScreenError.timeout: '切屏超时，请重试',
    FoldableScreenError.failed: '切屏失败，请重试',
    FoldableScreenError.busyExternal: '屏幕状态正由其他工具控制，请先恢复自动',
    FoldableScreenError.screenOff: '请先开启设备屏幕，再切换内外屏',
    FoldableScreenError.recording: '录屏期间无法切换内外屏',
  };
  for (final entry in errors.entries) {
    testWidgets('切屏错误保留状态并本地化反馈 ${entry.key}', (tester) async {
      final controller = _Controller(
        FoldableScreenUiState(snapshot: _innerSnapshot, error: entry.key),
      )..nextError = entry.key;
      await _pumpButton(tester, controller);
      expect(find.byKey(_innerIcon), findsOneWidget);
      expect(_tooltip(tester), contains(entry.value));
      await tester.tap(find.byKey(_button));
      await tester.pump();
      expect(controller.toggles, 1);
      expect(find.text(entry.value), findsOneWidget);
      AppToast.dismiss();
      await tester.pump();
    });
  }

  testWidgets('窗口销毁后的迟到结果不显示 Toast', (tester) async {
    final result = Completer<FoldableScreenError?>();
    final controller = _Controller(
      const FoldableScreenUiState(snapshot: _innerSnapshot),
    )..pending = result;
    await _pumpButton(tester, controller);
    await tester.tap(find.byKey(_button));
    await tester.pumpWidget(const SizedBox.shrink());
    result.complete(FoldableScreenError.failed);
    await tester.pump();
    expect(find.byKey(const Key('appToast')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实工具栏在切屏期间禁用录屏和物理息屏，结束后恢复', (tester) async {
    final controller = _Controller(
      const FoldableScreenUiState(snapshot: _innerSnapshot, isBusy: true),
    );
    await _pumpToolbar(tester, controller);
    final guarded = find.byWidgetPredicate(
      (widget) =>
          widget is MirrorToolbarButton &&
          (widget.shortcut == MirrorShortcut.recording ||
              widget.shortcut == MirrorShortcut.screenPower),
    );
    expect(guarded, findsNWidgets(2));
    for (final button in tester.widgetList<MirrorToolbarButton>(guarded)) {
      expect(button.isLoading, isTrue);
    }
    for (final button in tester.widgetList<IconButton>(
      find.descendant(of: guarded, matching: find.byType(IconButton)),
    )) {
      expect(button.onPressed, isNull);
    }
    controller.update(const FoldableScreenUiState(snapshot: _innerSnapshot));
    await tester.pump();
    for (final button in tester.widgetList<MirrorToolbarButton>(guarded)) {
      expect(button.isLoading, isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  for (final isHarmony in [false, true]) {
    testWidgets('非Android整机工具栏不订阅切屏状态 Harmony=$isHarmony', (tester) async {
      final controller = _Controller(
        const FoldableScreenUiState(snapshot: _innerSnapshot, isBusy: true),
      );
      await _pumpToolbar(
        tester,
        controller,
        isHarmony: isHarmony,
        isAppMirror: !isHarmony,
      );
      expect(controller.builds, 0);
      expect(find.byKey(_button), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
