import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/screenshot/controller/screenshot_controller.dart';
import 'package:any_deck/features/screenshot/model/screenshot_state.dart';
import 'package:any_deck/features/screenshot/widgets/screenshot_auto_save_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Screenshot Auto Save Tests', () {
    test('ScreenshotLayoutState has correct default autoSave values', () {
      const state = ScreenshotLayoutState();
      expect(state.isAutoSave, false);
      expect(state.autoSavePath, '');
      expect(state.autoRefreshInterval, 3);
      expect(state.autoSavedCount, 0);

      final modified = state.copyWith(
        isAutoSave: true,
        autoSavePath: '/test/path',
        autoRefreshInterval: 5,
        autoSavedCount: 2,
      );
      expect(modified.isAutoSave, true);
      expect(modified.autoSavePath, '/test/path');
      expect(modified.autoRefreshInterval, 5);
      expect(modified.autoSavedCount, 2);
    });

    test('ScreenshotController updates autoRefreshConfig properly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const deviceId = 'device_test_auto_save';
      final controller =
          container.read(screenshotLayoutControllerProvider(deviceId).notifier);

      controller.updateAutoRefreshConfig(
        autoSave: true,
        savePath: '/custom/save/dir',
        intervalSeconds: 2,
        startImmediately: false,
      );

      final state =
          container.read(screenshotLayoutControllerProvider(deviceId));
      expect(state.isAutoSave, true);
      expect(state.autoSavePath, '/custom/save/dir');
      expect(state.autoRefreshInterval, 2);
      expect(state.autoSavedCount, 0);
    });

    testWidgets('ScreenshotAutoSaveDialog renders components properly',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: ScreenshotAutoSaveDialog(deviceId: 'test_dev_01'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title and switch
      expect(find.byType(CupertinoSwitch), findsOneWidget);
      expect(find.text('1s'), findsOneWidget);
      expect(find.text('2s'), findsOneWidget);
      expect(find.text('3s'), findsOneWidget);
      expect(find.text('5s'), findsOneWidget);
      expect(find.text('10s'), findsOneWidget);
    });
  });
}
