import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/overview/model/android_version_distribution_data.dart';
import 'package:any_deck/features/overview/model/harmony_version_distribution_data.dart';
import 'package:any_deck/features/overview/model/ios_version_distribution_data.dart';
import 'package:any_deck/features/overview/model/platform_distribution_type.dart';
import 'package:any_deck/features/overview/widget/android_api_distribution_view.dart';
import 'package:any_deck/features/overview/widget/android_distribution_details_pane.dart';
import 'package:any_deck/features/overview/widget/harmony_api_distribution_view.dart';
import 'package:any_deck/features/overview/widget/harmony_distribution_details_pane.dart';
import 'package:any_deck/features/overview/widget/ios_distribution_details_pane.dart';
import 'package:any_deck/features/overview/widget/ios_version_distribution_view.dart';
import 'package:any_deck/features/overview/widget/platform_version_distribution_shell_view.dart';
import 'package:any_deck/features/overview/widget/platform_version_switcher.dart';
import 'package:any_deck/features/overview/widget/system_versions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 仅替换真实 Theme，页面及其版本选择持续挂载，不启动窗口或 URL 进程。
Future<ValueNotifier<AppThemeColor>> _mount(
  WidgetTester tester,
  Brightness brightness,
  Widget child,
) async {
  tester.view.physicalSize = const Size(1500, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final color = ValueNotifier(AppThemeColor.blue);
  addTearDown(color.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: ValueListenableBuilder<AppThemeColor>(
        valueListenable: color,
        builder: (context, value, child) => MaterialApp(
          theme: buildAppTheme(brightness, themeColor: value),
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: child,
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return color;
}

/// 检查真正的版本行选中装饰，图表条块仍使用数据模型中的颜色。
void _expectSelection(
  WidgetTester tester,
  PlatformDistributionType platform,
  ColorScheme colors,
) {
  if (platform == PlatformDistributionType.ios) {
    final selected = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .singleWhere((tile) => tile.selected);
    expect(selected.selectedTileColor, colors.primaryContainer);
    expect(selected.selectedColor, colors.onPrimaryContainer);
    return;
  }
  final view = platform == PlatformDistributionType.android
      ? find.byType(AndroidApiDistributionView)
      : find.byType(HarmonyApiDistributionView);
  final borderWidth = platform == PlatformDistributionType.harmony
      ? 1.5
      : colors.brightness == Brightness.dark
      ? 2.0
      : 2.5;
  final selected = tester
      .widgetList<Container>(
        find.descendant(of: view, matching: find.byType(Container)),
      )
      .where((widget) {
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.border is Border &&
            (decoration.border! as Border).top.width == borderWidth;
      })
      .single;
  final decoration = selected.decoration! as BoxDecoration;
  expect((decoration.border! as Border).top.color, colors.primary);
  if (platform == PlatformDistributionType.harmony) {
    expect(decoration.color, colors.primaryContainer);
    final item = tester
        .widget<HarmonyDistributionDetailsPane>(
          find.byType(HarmonyDistributionDetailsPane),
        )
        .item;
    for (final label in [
      '${item.apiNum}',
      'API 版本',
      item.share,
      '累计 ${item.cover}',
    ]) {
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byWidget(selected),
          matching: find.text(label),
        ),
      );
      final foreground = text.style!.color!;
      expect(foreground, colors.onPrimaryContainer, reason: label);
      final a = foreground.computeLuminance();
      final b = colors.primaryContainer.computeLuminance();
      final contrast = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: label);
    }
    final brandBlock = tester.widget<Container>(
      find
          .ancestor(
            of: find.descendant(
              of: find.byWidget(selected),
              matching: find.text(item.version),
            ),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (brandBlock.decoration! as BoxDecoration).color,
      const Color(0xFFE84335),
    );
  } else {
    final item = tester
        .widget<AndroidDistributionDetailsPane>(
          find.byType(AndroidDistributionDetailsPane),
        )
        .item;
    expect(decoration.color, item.barColor);
  }
}

Object _selectedItem(WidgetTester tester, PlatformDistributionType platform) =>
    switch (platform) {
      PlatformDistributionType.android =>
        tester
            .widget<AndroidDistributionDetailsPane>(
              find.byType(AndroidDistributionDetailsPane),
            )
            .item,
      PlatformDistributionType.harmony =>
        tester
            .widget<HarmonyDistributionDetailsPane>(
              find.byType(HarmonyDistributionDetailsPane),
            )
            .item,
      PlatformDistributionType.ios =>
        tester
            .widget<IosDistributionDetailsPane>(
              find.byType(IosDistributionDetailsPane),
            )
            .item,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? copied;
  setUp(() {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final brightness in Brightness.values) {
    for (final platform in PlatformDistributionType.values) {
      testWidgets('系统版本 $platform 在 $brightness 换色并保留版本选择和复制', (tester) async {
        final color = await _mount(
          tester,
          brightness,
          const SystemVersionsPage(),
        );
        final switcher = find.byType(PlatformVersionSwitcher);
        final platformLabel = find.descendant(
          of: switcher,
          matching: find.text(platform.displayName),
        );
        await tester.tap(platformLabel);
        // 桌面 Header 的 DragToMoveArea 注册双击，单击需等待双击判定完成。
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        final versionView = switch (platform) {
          PlatformDistributionType.android => find.byType(
            AndroidApiDistributionView,
          ),
          PlatformDistributionType.harmony => find.byType(
            HarmonyApiDistributionView,
          ),
          PlatformDistributionType.ios => find.byType(
            IosVersionDistributionView,
          ),
        };
        expect(versionView, findsOneWidget);

        final versionLabel = switch (platform) {
          PlatformDistributionType.android => find.text(
            '${AndroidVersionDistributionData.items.reversed.skip(1).first.platformVersion}   '
            '${AndroidVersionDistributionData.items.reversed.skip(1).first.codename}',
          ),
          PlatformDistributionType.harmony => find.text(
            HarmonyVersionDistributionData.items[1].version,
          ),
          PlatformDistributionType.ios => find.widgetWithText(
            ListTile,
            'iOS ${IosVersionDistributionData.items[1].version}',
          ),
        };
        // 版本列表按视口延迟构建，先滚动实际左栏，再定位目标条目。
        await tester.scrollUntilVisible(
          versionLabel,
          100,
          scrollable: find
              .descendant(of: versionView, matching: find.byType(Scrollable))
              .first,
          maxScrolls: 20,
        );
        await tester.tap(versionLabel);
        await tester.pumpAndSettle();
        final selected = _selectedItem(tester, platform);
        final pageElement = tester.element(find.byType(SystemVersionsPage));

        for (final value in [AppThemeColor.blue, AppThemeColor.purple]) {
          color.value = value;
          await tester.pumpAndSettle();
          expect(
            tester.element(find.byType(SystemVersionsPage)),
            same(pageElement),
          );
          expect(_selectedItem(tester, platform), same(selected));
          final theme = Theme.of(tester.element(switcher));
          final colors = theme.colorScheme;
          final selection =
              tester
                      .widget<AnimatedContainer>(
                        find.ancestor(
                          of: platformLabel,
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!
                  as BoxDecoration;
          expect(selection.color, theme.appColors.panelSurface);
          expect(
            tester.widget<Text>(platformLabel).style?.color,
            colors.onSurface,
          );
          _expectSelection(tester, platform, colors);

          final copies = find.byIcon(Icons.copy_rounded);
          expect(copies, findsWidgets);
          for (final icon in tester.widgetList<Icon>(copies)) {
            expect(icon.color, value.color);
          }
          final url = switch (selected) {
            AndroidDistributionItem item => item.summaryUrl!,
            HarmonyDistributionItem item => item.link,
            IosDistributionItem item => item.link,
            _ => throw StateError('未知版本数据'),
          };
          expect(tester.widget<Text>(find.text(url)).style?.color, value.color);
        }
        final copy = find.byIcon(Icons.copy_rounded).first;
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(copied, isNotEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    for (final shell in [false, true]) {
      testWidgets('版本页面关闭按钮在 $brightness 换色且回调保留 shell=$shell', (tester) async {
        var closed = 0;
        final color = await _mount(
          tester,
          brightness,
          shell
              ? PlatformVersionDistributionShellView(onClose: () => closed++)
              : AndroidApiDistributionView(onClose: () => closed++),
        );
        for (final value in [AppThemeColor.blue, AppThemeColor.purple]) {
          color.value = value;
          await tester.pumpAndSettle();
          final close = tester.widget<ElevatedButton>(
            find.byType(ElevatedButton),
          );
          expect(close.style?.backgroundColor?.resolve({}), value.color);
          expect(close.style?.foregroundColor?.resolve({}), Colors.white);
        }
        await tester.tap(find.byType(ElevatedButton));
        expect(closed, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
