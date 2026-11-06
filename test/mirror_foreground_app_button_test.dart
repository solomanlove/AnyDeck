import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/shortcuts/mirror_shortcut_scope.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/app/window/mirror/app_mirror_launch_coordinator.dart';
import 'package:any_deck/app/window/mirror/widget/mirror_foreground_app_button.dart';
import 'package:any_deck/app/window/mirror/widget/mirror_window_title_bar.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/scrcpy/fusion_mode_preference.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shortcut_test_fixture.dart';

const _appActionKey = Key('foreground-app-action');

/// 使用真实标题栏层级检查手势，避免只调用 callback 而漏掉拖拽区域冲突。
Future<void> _pumpHeader(
  WidgetTester tester, {
  required Future<void> Function() onOpen,
  VoidCallback? onQuickActions,
  VoidCallback? onRetry,
  VoidCallback? onToggleAlwaysOnTop,
  VoidCallback? onToggleFullScreen,
  VoidCallback? onSettings,
  String language = 'zh',
  Brightness brightness = Brightness.light,
  FusionModeState mode = FusionModeState.enabled,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsProvider.overrideWith(ShortcutTestSettings.new),
        deviceFusionModeProvider(
          'phone',
        ).overrideWith((ref) async => FusionModeStatus(mode)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(brightness),
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: MirrorShortcutScope(
            child: Align(
              alignment: Alignment.topLeft,
              child: Builder(
                builder: (context) => MirrorWindowTitleBar(
                  deviceName: 'PNM AN10',
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  isIos: false,
                  isAudioForwarded: false,
                  isMirrorActive: false,
                  isAlwaysOnTop: false,
                  isFullScreen: false,
                  onTitleHoverChanged: (_) {},
                  onRetry: onRetry ?? () {},
                  onToggleAlwaysOnTop: onToggleAlwaysOnTop ?? () {},
                  onToggleFullScreen: onToggleFullScreen ?? () {},
                  onSettings: onSettings,
                  foregroundAppAction: MirrorForegroundAppButton(
                    key: _appActionKey,
                    deviceId: 'phone',
                    package: AdbPackage(
                      name: 'com.example.gallery',
                      label: '图库',
                    ),
                    onOpen: onOpen,
                    onQuickActions: onQuickActions ?? () {},
                  ),
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

/// 不执行 ADB，只提供融合路由所需的 SDK 和已有图库 Task。
class _AdbFake extends AdbService {
  _AdbFake() : super(executable: 'adb');

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async => AdbResult(
    exitCode: 0,
    stdout: args.contains('ro.build.version.sdk')
        ? '36'
        : 'RootTask id=42 displayId=0\n'
              '  taskId=42: com.example.gallery/.MainActivity\n',
    stderr: '',
  );
}

class _StoreFake implements FusionModeStore {
  @override
  Future<bool?> read(String key) async => true;

  @override
  Future<void> write(String key, bool enabled) async {}
}

class _WindowsFake implements AppMirrorWindowGateway {
  final created = <Map<String, dynamic>>[];
  final firstFrame = Completer<void>();
  int waits = 0;

  @override
  Future<String?> focusFusion(
    String deviceId,
    String? physicalKey,
    String packageName,
  ) async => null;

  @override
  Future<String> create(
    Map<String, dynamic> arguments,
    Size size,
    String title,
  ) async {
    created.add(arguments);
    return 'fusion-window';
  }

  @override
  Future<void> waitForFusionFrame(String windowId) async {
    waits++;
    await firstFrame.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  final windowCalls = <String>[];

  setUp(() {
    windowCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
          windowCalls.add(call.method);
          return call.method == 'isMaximized' ? false : null;
        });
  });

  tearDown(() {
    AppToast.dismiss();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
  });

  testWidgets('图标周围可点击，立即进入融合路由并等待首帧，连点只创建一次', (tester) async {
    final adb = _AdbFake();
    final windows = _WindowsFake();
    final coordinator = AppMirrorLaunchCoordinator(
      adb,
      FusionModePreference(adb, store: _StoreFake()),
      windows: windows,
    );
    await _pumpHeader(
      tester,
      onOpen: () async {
        await coordinator.open(
          const AppMirrorLaunchRequest(
            deviceId: 'phone',
            packageName: 'com.example.gallery',
            appName: '图库',
            mirrorTitleTemplate: '投屏 - {name}',
            alwaysOnTop: true,
          ),
        );
      },
    );
    final action = find.byKey(_appActionKey);
    expect(tester.getSize(action), const Size(28, 28));
    final padding = tester.getTopLeft(action) + const Offset(1, 14);
    await tester.tapAt(padding, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(windows.created, hasLength(1));
    expect(windows.created.single['startApp'], 'com.example.gallery');
    expect(windows.created.single['newDisplay'], isNotNull);
    expect(windows.created.single['alwaysOnTop'], isTrue);
    expect(windows.waits, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tapAt(padding, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(windows.created, hasLength(1));
    expect(windowCalls, isEmpty);

    windows.firstFrame.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('长按和右键保留快捷操作，启动等待期间拦截快捷操作', (tester) async {
    var opened = 0;
    var quickActions = 0;
    final pending = Completer<void>();
    await _pumpHeader(
      tester,
      onOpen: () {
        opened++;
        return pending.future;
      },
      onQuickActions: () => quickActions++,
    );
    final action = find.byKey(_appActionKey);
    await tester.tap(
      action,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.longPress(action);
    await tester.pumpAndSettle();
    expect(quickActions, 2);
    expect(opened, 0);

    await tester.tap(action, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tap(
      action,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.longPress(action);
    await tester.pump();
    expect(opened, 1);
    expect(quickActions, 2);
    expect(windowCalls, isEmpty);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('标题仍可拖动和双击最大化，图标双击不触发窗口动作', (tester) async {
    var opened = 0;
    await _pumpHeader(tester, onOpen: () async => opened++);
    final action = find.byKey(_appActionKey);
    await tester.tap(action, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(action, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(opened, 2);
    expect(windowCalls, isEmpty);

    final title = find.text('PNM AN10');
    await tester.drag(
      title,
      const Offset(40, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(windowCalls, contains('startDragging'));
    windowCalls.clear();
    await tester.tap(title, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(title, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(windowCalls, containsAll(['isMaximized', 'maximize']));
  });

  testWidgets('启动失败显示错误并恢复点击，等待结束前关闭窗口安全', (tester) async {
    var opened = 0;
    final pending = Completer<void>();
    await _pumpHeader(
      tester,
      onOpen: () async {
        if (++opened == 1) throw StateError('test launch failed');
        await pending.future;
      },
    );
    final action = find.byKey(_appActionKey);
    await tester.tap(action, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('test launch failed'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    AppToast.dismiss();
    await tester.tap(action, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(opened, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('窄窗口中英文与明暗主题入口可用 $language $brightness', (tester) async {
        tester.view.physicalSize = const Size(320, 160);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pumpHeader(
          tester,
          onOpen: () async {},
          language: language,
          brightness: brightness,
        );
        expect(
          find.byTooltip(
            language == 'zh'
                ? '融合投屏 · 长按或右键打开快捷操作'
                : 'Fusion mirroring · Long press or right click for quick actions',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('关闭融合时入口提示普通投屏', (tester) async {
    await _pumpHeader(
      tester,
      onOpen: () async {},
      mode: FusionModeState.disabled,
    );
    expect(find.byTooltip('普通投屏 · 长按或右键打开快捷操作'), findsOneWidget);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('标题栏独立命中后保留窗口快捷键 $platform', (tester) async {
      final invoked = <String>[];
      await _pumpHeader(
        tester,
        onOpen: () async {},
        onRetry: () => invoked.add('retry'),
        onToggleAlwaysOnTop: () => invoked.add('pin'),
        onToggleFullScreen: () => invoked.add('fullscreen'),
        onSettings: () => invoked.add('settings'),
      );
      final modifier = platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      for (final key in [
        LogicalKeyboardKey.keyX,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.keyQ,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyUpEvent(modifier);
      }
      expect(invoked, ['retry', 'pin', 'fullscreen', 'settings']);
      expect(windowCalls, isEmpty);
    }, variant: TargetPlatformVariant({platform}));
  }
}
