import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/device_os_logo_widget.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/environment/connection_environment_service.dart';
import 'package:any_deck/features/developer/widget/developer_connection_environment_card.dart';
import 'package:any_deck/features/overview/model/platform_distribution_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shortcut_test_fixture.dart';

/// 固定环境结果，验证 UI 时不探测 CLI 或运行后台进程。
class _Environment extends ConnectionEnvironmentNotifier {
  int checks = 0;
  @override
  Future<Map<TargetPlatformType, PlatformEnvironmentInfo>> checkAll() async {
    checks++;
    return state;
  }
}

class _Adb extends AdbEnvironmentNotifier {
  @override
  AdbEnvironmentInfo build() => const AdbEnvironmentInfo(
    status: AdbEnvironmentStatus.ready,
    version: 'test',
    adbPath: '/test/adb',
  );
  @override
  Future<AdbEnvironmentInfo> check() async => state;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness 公共平台 Logo 支持不同尺寸与 Apple 主题对比度', (tester) async {
      final theme = buildAppTheme(brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                for (final size in [15.0, 20.0, 48.0])
                  Row(
                    children: [
                      for (final platform in PlatformDistributionType.values)
                        buildPlatformIcon(platform, size: size),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final apple = find.byIcon(Icons.apple);
      expect(apple, findsNWidgets(3));
      expect(
        tester.widgetList<Icon>(apple).map((icon) => icon.color),
        everyElement(theme.colorScheme.onSurface),
      );
      expect(tester.widgetList<Icon>(apple).map((icon) => icon.size), [
        15,
        20,
        48,
      ]);
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => image.width),
        [15, 20, 48],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$brightness 诊断卡片六处平台 Logo 加载且保留检测与平台引导', (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          connectionEnvironmentProvider.overrideWith(_Environment.new),
          adbEnvironmentProvider.overrideWith(_Adb.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        shortcutTestApp(
          container: container,
          brightness: brightness,
          child: const SingleChildScrollView(
            child: DeveloperConnectionEnvironmentCard(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.android_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.apple), findsNWidgets(2));
      expect(find.byType(Image), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      final environment =
          container.read(connectionEnvironmentProvider.notifier)
              as _Environment;
      expect(environment.checks, 1);
      await tester.tap(find.text('重新检测全部'));
      await tester.pumpAndSettle();
      expect(environment.checks, 2);
      await tester.tap(find.text('鸿蒙 HDC 引导测试'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      expect(environment.checks, 4);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
