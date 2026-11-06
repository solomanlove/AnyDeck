import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/shortcuts/mirror_shortcut_scope.dart';
import 'package:any_deck/app/shortcuts/window_shortcut.dart';
import 'package:any_deck/app/window/mirror/mirror_toolbar_button.dart';
import 'package:any_deck/app/window/window_close_shortcut.dart';
import 'package:any_deck/app/window/window_shortcut_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shortcut_test_fixture.dart';

/// 验证真实窗口响应、配置变更、旧组合失效，以及子窗口到主窗口的转发。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = ShortcutPlatformMocks();
  setUp(platform.setUp);
  tearDown(platform.tearDown);

  ProviderContainer container() => ProviderContainer(
    overrides: [appSettingsProvider.overrideWith(ShortcutTestSettings.new)],
  );

  testWidgets('子窗口默认关闭组合键只关闭当前窗口', (tester) async {
    final state = container();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      shortcutTestApp(
        container: state,
        child: const WindowCloseShortcut(child: Text('window')),
      ),
    );
    await tester.pump();
    await _primary(tester, LogicalKeyboardKey.keyW);
    expect(platform.windowCalls, ['close']);
    await _unmount(tester);
  });

  testWidgets('主窗口保留旧唤起键，三个默认操作调用原有入口', (tester) async {
    final state = container();
    addTearDown(state.dispose);
    var quits = 0;
    var settings = 0;
    await tester.pumpWidget(
      shortcutTestApp(
        container: state,
        child: MainWindowCloseShortcut(
          showWindowKey: '5',
          onQuit: () => quits++,
          onOpenSettings: () => settings++,
          child: const Text('main'),
        ),
      ),
    );
    await tester.pump();
    await _primary(tester, LogicalKeyboardKey.digit1);
    expect(platform.windowCalls, isEmpty);
    await _primary(tester, LogicalKeyboardKey.digit5);
    expect(platform.windowCalls, containsAllInOrder(['show', 'focus']));
    platform.windowCalls.clear();
    await _primary(tester, LogicalKeyboardKey.keyW);
    expect(platform.windowCalls, ['close']);
    await _primary(tester, LogicalKeyboardKey.comma);
    await _primary(tester, LogicalKeyboardKey.keyQ);
    expect(settings, 1);
    expect(quits, 1);
    await _unmount(tester);
  });

  testWidgets('主窗口唤起组合在输入控件之前匹配，额外修饰键不触发', (tester) async {
    final state = container();
    addTearDown(state.dispose);
    final forwarded = <LogicalKeyboardKey>[];
    const binding = KeyboardShortcutBinding(
      key: LogicalKeyboardKey.keyK,
      control: true,
      shift: true,
    );
    await tester.pumpWidget(
      shortcutTestApp(
        container: state,
        child: MainWindowCloseShortcut(
          showWindowShortcut: binding,
          child: Focus(
            onKeyEvent: (_, event) {
              forwarded.add(event.logicalKey);
              return KeyEventResult.handled;
            },
            child: const Text('input'),
          ),
        ),
      ),
    );
    await tester.pump();
    Focus.of(tester.element(find.text('input'))).requestFocus();
    await tester.pump();
    await pressShortcut(
      tester,
      binding.key!,
      modifiers: [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft],
    );
    expect(platform.windowCalls, containsAllInOrder(['show', 'focus']));
    expect(forwarded, isNot(contains(binding.key)));
    platform.windowCalls.clear();
    await pressShortcut(
      tester,
      binding.key!,
      modifiers: [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.altLeft,
      ],
    );
    expect(platform.windowCalls, isEmpty);
    expect(forwarded, contains(binding.key));
    await tester.pumpWidget(
      shortcutTestApp(
        container: state,
        child: const MainWindowCloseShortcut(
          showWindowShortcut: KeyboardShortcutBinding.disabled(),
          child: Text('disabled'),
        ),
      ),
    );
    await tester.pump();
    await _primary(tester, LogicalKeyboardKey.digit1);
    expect(platform.windowCalls, isEmpty);
    await _unmount(tester);
  });

  for (final target in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('$target 三个窗口操作改绑立即生效，旧组合、repeat 和禁用均不误触发', (tester) async {
      final state = container();
      addTearDown(state.dispose);
      var settings = 0;
      var quits = 0;
      await tester.pumpWidget(
        shortcutTestApp(
          container: state,
          child: MainWindowCloseShortcut(
            onOpenSettings: () => settings++,
            onQuit: () => quits++,
            child: Focus(
              onKeyEvent: (_, event) => KeyEventResult.handled,
              child: const Text('input'),
            ),
          ),
        ),
      );
      await tester.pump();
      Focus.of(tester.element(find.text('input'))).requestFocus();
      await tester.pump();
      var changed = const WindowShortcutSettings();
      for (final action in WindowShortcut.values) {
        changed = changed.withBinding(
          action,
          KeyboardShortcutBinding(
            key: [
              LogicalKeyboardKey.f10,
              LogicalKeyboardKey.f11,
              LogicalKeyboardKey.f12,
            ][action.index],
            control: true,
            shift: true,
          ),
        );
      }
      await state
          .read(appSettingsProvider.notifier)
          .setWindowShortcuts(changed);
      await tester.pump();
      await _primary(tester, LogicalKeyboardKey.keyW);
      await _primary(tester, LogicalKeyboardKey.comma);
      await _primary(tester, LogicalKeyboardKey.keyQ);
      expect(platform.windowCalls, isEmpty);
      expect(settings, 0);
      expect(quits, 0);
      for (final action in WindowShortcut.values) {
        await pressShortcut(
          tester,
          changed.bindingFor(action).key!,
          modifiers: [
            LogicalKeyboardKey.controlRight,
            LogicalKeyboardKey.shiftRight,
          ],
        );
      }
      expect(
        platform.windowCalls.where((method) => method == 'close'),
        hasLength(1),
      );
      expect(settings, 1);
      expect(quits, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f12);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f12);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f12);
      await tester.pump();
      expect(quits, 2);
      var disabled = changed;
      for (final action in WindowShortcut.values) {
        disabled = disabled.withBinding(
          action,
          const KeyboardShortcutBinding.disabled(),
        );
      }
      await state
          .read(appSettingsProvider.notifier)
          .setWindowShortcuts(disabled);
      await tester.pump();
      await pressShortcut(
        tester,
        LogicalKeyboardKey.f12,
        modifiers: [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.shiftLeft,
        ],
      );
      expect(quits, 2);
      await _unmount(tester);
    }, variant: TargetPlatformVariant({target}));
  }

  testWidgets('子窗口转发设置和退出，旧关闭键释放后用于投屏，错误请求不关闭主窗口', (tester) async {
    final state = container();
    addTearDown(state.dispose);
    platform.forwardRequests = true;
    var settings = 0;
    var quits = 0;
    var screenshots = 0;
    await tester.pumpWidget(
      shortcutTestApp(
        container: state,
        child: Row(
          children: [
            Expanded(
              child: MainWindowCloseShortcut(
                onOpenSettings: () => settings++,
                onQuit: () => quits++,
                child: const Text('main'),
              ),
            ),
            Expanded(
              child: WindowCloseShortcut(
                autofocus: false,
                child: MirrorShortcutScope(
                  child: Column(
                    children: [
                      Focus(
                        onKeyEvent: (_, event) => KeyEventResult.handled,
                        child: const Text('child'),
                      ),
                      MirrorToolbarButton(
                        icon: const Icon(Icons.camera),
                        tooltip: 'capture',
                        shortcut: MirrorShortcut.screenshot,
                        onPressed: () => screenshots++,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    Focus.of(tester.element(find.text('child'))).requestFocus();
    await tester.pump();
    var changed = const WindowShortcutSettings()
        .withBinding(
          WindowShortcut.closeWindow,
          const KeyboardShortcutBinding(key: LogicalKeyboardKey.f7),
        )
        .withBinding(
          WindowShortcut.openSettings,
          const KeyboardShortcutBinding(key: LogicalKeyboardKey.f5),
        )
        .withBinding(
          WindowShortcut.quitApp,
          const KeyboardShortcutBinding(key: LogicalKeyboardKey.f6),
        );
    await state.read(appSettingsProvider.notifier).setWindowShortcuts(changed);
    final previousClose = WindowShortcut.closeWindow.defaultBinding;
    await state
        .read(appSettingsProvider.notifier)
        .setMirrorShortcuts(
          const MirrorShortcutSettings().withBinding(
            MirrorShortcut.screenshot,
            previousClose,
          ),
        );
    await tester.pump();
    await _primary(tester, LogicalKeyboardKey.keyW);
    expect(screenshots, 1);
    expect(platform.windowCalls, isEmpty);
    await pressShortcut(tester, LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(settings, 1);
    expect(platform.windowCalls, containsAllInOrder(['show', 'focus']));
    await pressShortcut(tester, LogicalKeyboardKey.f6);
    await tester.pumpAndSettle();
    expect(quits, 1);
    expect(
      platform.channelCalls.where(
        (call) => call['channel'] == WindowShortcutBridge.channelName,
      ),
      hasLength(2),
    );
    expect(
      () => WindowShortcutBridge.request(WindowShortcut.closeWindow),
      throwsArgumentError,
    );
    final ignoredClose = platform.deliverWindowAction('closeWindow');
    await tester.pump();
    await ignoredClose;
    final ignoredValue = platform.deliverWindowAction(42);
    await tester.pump();
    await ignoredValue;
    expect(platform.windowCalls.where((method) => method == 'close'), isEmpty);
    await pressShortcut(tester, LogicalKeyboardKey.f7);
    expect(
      platform.windowCalls.where((method) => method == 'close'),
      hasLength(1),
    );
    await _unmount(tester);
  });

  test('主窗口 Channel 生命周期串行化，旧窗口注销不会覆盖新回调', () async {
    final oldOwner = Object();
    final newOwner = Object();
    var oldCalls = 0;
    var newCalls = 0;
    await WindowShortcutBridge.register(oldOwner, (_) async => oldCalls++);
    final removed = WindowShortcutBridge.unregister(oldOwner);
    final registered = WindowShortcutBridge.register(
      newOwner,
      (_) async => newCalls++,
    );
    await Future.wait([removed, registered]);
    await WindowShortcutBridge.unregister(oldOwner);
    await platform.deliverWindowAction(WindowShortcut.openSettings.name);
    expect(oldCalls, 0);
    expect(newCalls, 1);
    await WindowShortcutBridge.unregister(newOwner);
  });
}

Future<void> _primary(WidgetTester tester, LogicalKeyboardKey key) =>
    pressShortcut(
      tester,
      key,
      modifiers: [
        KeyboardShortcutBinding.isMacOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft,
      ],
    );

/// 显式等待自动注销完成，避免测试的 FakeAsync zone 结束后留下未完成的 Channel 任务。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var settled = false;
  final completion = WindowShortcutBridge.settled.then((_) => settled = true);
  for (var i = 0; i < 20 && !settled; i++) {
    await tester.pump();
  }
  expect(settled, true);
  await completion;
}
