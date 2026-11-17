import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/window/console/console_window_app.dart';
import 'package:any_deck/app/window/console/console_window_panel.dart';
import 'package:any_deck/core/logging/log_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只驱动窗口外观状态，避免测试启动真实设置广播和文件读取。
class _Settings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings(themeColor: AppThemeColor.blue);

  void changeColor(AppThemeColor color) =>
      state = state.copyWith(themeColor: color);
}

/// 独立控制台读取空日志，避免跨窗口同步及实际磁盘访问。
class _Logs extends LogService {
  @override
  List<String> build() => [];

  @override
  Future<void> syncHistory() async {}
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('控制台子窗口在 $brightness 跟随主题色更新', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(_Settings.new),
          logHistoryProvider.overrideWith(_Logs.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ConsoleWindowApp(windowId: 'console-test', argument: {}),
        ),
      );
      await tester.pumpAndSettle();

      void expectColor(AppThemeColor color) {
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(app.theme?.colorScheme.primary, color.color);
        expect(app.darkTheme?.colorScheme.primary, color.color);
        final theme = Theme.of(tester.element(find.byType(ConsoleWindowPanel)));
        expect(theme.brightness, brightness);
        expect(theme.colorScheme.primary, color.color);
      }

      expectColor(AppThemeColor.blue);
      (container.read(appSettingsProvider.notifier) as _Settings).changeColor(
        AppThemeColor.purple,
      );
      await tester.pumpAndSettle();
      expectColor(AppThemeColor.purple);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
