import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/apps/app_permission_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/apps/widgets/app_permissions_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/permission_adb_fake.dart';

/// 用 Widget 测试验证窄弹窗、主题、分类及批量操作实际范围。
void main() {
  for (final locale in ['zh', 'en']) {
    testWidgets('$locale 窄面板分类只读与全部撤销', (tester) async {
      final fake = PermissionAdbFake();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPermissionServiceProvider.overrideWithValue(
              AppPermissionService(fake),
            ),
          ],
          child: MaterialApp(
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            theme: ThemeData(
              brightness: locale == 'zh' ? Brightness.light : Brightness.dark,
            ),
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 492,
                  height: 480,
                  child: AppPermissionsPanel(
                    deviceId: 'device',
                    packageName: 'com.example.app',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 虚拟列表只构建可见行，数量以分类统计为准。
      expect(find.text(locale == 'zh' ? '动态权限 (3)' : 'Runtime (3)'), findsOneWidget);
      expect(find.byType(Switch), findsWidgets);
      await tester.tap(find.text(locale == 'zh' ? '静态权限 (1)' : 'Static (1)'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
      expect(find.text('android.permission.INTERNET'), findsOneWidget);
      await tester.tap(
        find.text(locale == 'zh' ? '撤销所有权限' : 'Revoke All Permissions'),
      );
      // 确认期间操作锁对应的进度条持续动画，无需等待其停止。
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(locale == 'zh' ? '确认' : 'Confirm'));
      await tester.pumpAndSettle();
      expect(fake.cameraGranted, isFalse);
      expect(fake.micGranted, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
