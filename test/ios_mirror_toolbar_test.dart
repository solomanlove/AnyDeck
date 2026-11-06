import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/window/mirror/ios_mirror_toolbar.dart';
import 'package:any_deck/app/window/mirror/mirror_toolbar_button.dart';
import 'package:any_deck/features/control/whiteboard/mirror_whiteboard_controller.dart';
import 'package:any_deck/core/ios/ios_control_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 无真机测试 iOS 能力入口、状态门禁和两套主题/语言，防止再次混入 Android 操作。
void main() {
  for (final locale in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('$locale $brightness shows only supported iOS actions', (
        tester,
      ) async {
        var ready = false;
        var screenshots = 0;
        var saved = 0;
        final whiteboard = MirrorWhiteboardController();
        addTearDown(whiteboard.dispose);
        final calls = <String>[];
        final container = ProviderContainer(
          overrides: [
            iosControlCallProvider.overrideWithValue((
              udid,
              action, [
              args = const {},
            ]) async {
              calls.add('$action:${args['name'] ?? ''}');
              return {'ready': ready, 'width': 375, 'height': 667};
            }),
          ],
        );
        var disposed = false;
        addTearDown(() {
          if (!disposed) container.dispose();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: Locale(locale),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: IosMirrorToolbar(
                  deviceId: 'phone',
                  onScreenshot: () => screenshots++,
                  onSaveScreenshot: () => saved++,
                  whiteboard: whiteboard,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final buttons = tester
            .widgetList<MirrorToolbarButton>(find.byType(MirrorToolbarButton))
            .toList();
        expect(buttons, hasLength(9));
        expect(buttons.take(5).every((b) => b.onPressed == null), true);
        expect(buttons.last.onPressed, isNotNull);
        expect(find.byIcon(CupertinoIcons.scope), findsNothing);
        expect(
          find.byKey(const ValueKey('ios-usb-record-toggle')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mirror-whiteboard-toggle')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('ios-control-toggle')),
          findsOneWidget,
        );
        expect(
          tester.getCenter(find.byIcon(CupertinoIcons.camera)).dy,
          lessThan(
            tester
                .getCenter(find.byKey(const ValueKey('ios-control-toggle')))
                .dy,
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('mirror-whiteboard-toggle')),
        );
        await tester.pump();
        expect(whiteboard.active, isTrue);
        expect(
          find.byKey(const ValueKey('mirror-whiteboard-color')),
          findsOneWidget,
        );
        await tester.tap(find.byIcon(CupertinoIcons.camera));
        await tester.longPress(find.byIcon(CupertinoIcons.camera));
        expect(screenshots, 1);
        expect(saved, 1);

        ready = true;
        await container.read(iosControlProvider('phone').notifier).refresh();
        await tester.pump();
        await tester.tap(find.byIcon(Icons.radio_button_unchecked));
        await tester.pump();
        expect(calls, contains('button:home'));
        final volume = tester.widget<MirrorToolbarButton>(
          find.ancestor(
            of: find.byIcon(CupertinoIcons.volume_up),
            matching: find.byType(MirrorToolbarButton),
          ),
        );
        expect(volume.onPointerDown, isNull);
        expect(volume.onLongPress, isNull);

        ready = false;
        await container.read(iosControlProvider('phone').notifier).refresh();
        await tester.pump();
        expect(
          tester
              .widgetList<MirrorToolbarButton>(find.byType(MirrorToolbarButton))
              .take(5)
              .every((b) => b.onPressed == null),
          true,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        disposed = true;
      });
    }
  }

  testWidgets('control failure opens a scrollable error dialog', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        iosControlCallProvider.overrideWithValue((
          udid,
          action, [
          args = const {},
        ]) async {
          if (action == 'start') {
            throw StateError('WDA diagnostic details');
          }
          return {'ready': false};
        }),
      ],
    );
    var disposed = false;
    addTearDown(() {
      if (!disposed) container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: IosMirrorToolbar(
              deviceId: 'phone',
              onScreenshot: _noop,
              onSaveScreenshot: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ios-control-toggle')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('WDA diagnostic details'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    disposed = true;
  });
}

void _noop() {}
