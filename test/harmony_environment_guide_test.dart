import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/environment/connection_environment_service.dart';
import 'package:any_deck/features/devices/widgets/platform_environment_guide_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证鸿蒙安装引导在两种语言下都能打开所选工具的官方下载页。
void main() {
  for (final language in ['zh', 'en']) {
    testWidgets('鸿蒙安装引导的两个下载按钮分别打开对应页面（$language）', (tester) async {
      tester.view.physicalSize = const Size(850, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final openedUrls = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionEnvironmentProvider.overrideWith(_OfflineEnvironment.new),
          ],
          child: MaterialApp(
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: PlatformEnvironmentGuideDialog(
              initialPlatform: TargetPlatformType.harmony,
              onOpenHarmonyDownload: (url) async => openedUrls.add(url),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(language == 'zh' ? '获取 HDC（任选一种）' : 'Get HDC (choose one)'),
        findsOneWidget,
      );
      final download = language == 'zh' ? '下载' : 'Download';
      for (final tool in ['Command Line Tools', 'DevEco Studio']) {
        final button = find.text('$download $tool');
        expect(button, findsOneWidget);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      expect(openedUrls, [
        'https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos',
        'https://developer.huawei.com/consumer/cn/download/deveco-studio',
      ]);
    });
  }
}

/// 模拟本机缺少 HDC，弹窗打开时无需调用真实 CLI。
class _OfflineEnvironment extends ConnectionEnvironmentNotifier {
  @override
  Future<Map<TargetPlatformType, PlatformEnvironmentInfo>> checkAll() async {
    simulateMissing(TargetPlatformType.harmony);
    return state;
  }
}
