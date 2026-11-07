import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/devices/widgets/emulator_platform_tabs.dart';
import 'package:any_deck/features/overview/model/platform_distribution_type.dart';
import 'package:any_deck/features/overview/widget/platform_version_switcher.dart';
import 'package:any_deck/features/widgets/dashboard_header_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证模拟器平台适配与受控选中状态，不启动真实模拟器或平台服务。
void main() {
  const platforms = {
    EmulatorPlatform.android: PlatformDistributionType.android,
    EmulatorPlatform.harmony: PlatformDistributionType.harmony,
    EmulatorPlatform.ios: PlatformDistributionType.ios,
  };

  for (final brightness in Brightness.values) {
    for (final initial in EmulatorPlatform.values) {
      testWidgets('$brightness / $initial 复用系统版本 Tab 并正确切换平台', (tester) async {
        var selected = initial;
        final changes = <EmulatorPlatform>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            home: Scaffold(
              body: SizedBox(
                width: 650,
                child: StatefulBuilder(
                  builder: (context, setState) => DashboardHeaderBar(
                    title: '模拟器管理',
                    subtitle: 'Android AVD、DevEco Emulator、Xcode Simulator',
                    trailing: EmulatorPlatformTabs(
                      selectedPlatform: selected,
                      onPlatformChanged: (platform) {
                        changes.add(platform);
                        setState(() => selected = platform);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final switcher = find.byType(PlatformVersionSwitcher);
        expect(switcher, findsOneWidget);
        expect(
          tester.widget<PlatformVersionSwitcher>(switcher).selectedPlatform,
          platforms[initial],
        );
        for (final platform in EmulatorPlatform.values) {
          expect(find.text(platform.label), findsOneWidget);
          await tester.tap(find.text(platform.label));
          // 标题栏支持双击最大化，等待其双击识别窗口结束再验证单击回调。
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
          expect(selected, platform);
          expect(changes.last, platform);
          expect(
            tester.widget<PlatformVersionSwitcher>(switcher).selectedPlatform,
            platforms[platform],
          );
          expect(tester.takeException(), isNull);
        }
        expect(changes, EmulatorPlatform.values);
      });
    }
  }
}
