import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/devices/model/device_workspace_view_state.dart';
import 'package:any_deck/features/devices/widgets/device_list_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 分组工具栏使用真实文本布局验证组合宽度，不启动设备发现或桌面应用。
void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('分组工具栏 $language ${brightness.name} 自适应且搜索可用', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final queries = <String>[];
        var groupTaps = 0;

        for (final scale in [1.0, 1.6]) {
          for (final width in [320.0, 360.0, 720.0, 920.0, 1200.0]) {
            tester.view.physicalSize = Size(width, 900);
            await tester.pumpWidget(
              _host(
                language: language,
                brightness: brightness,
                scale: scale,
                child: DeviceListFilters(
                  controller: controller,
                  onlineCount: 2,
                  totalCount: 6,
                  filter: DeviceStatusFilter.all,
                  onFilterChanged: (_) {},
                  viewMode: DeviceViewMode.list,
                  onViewModeChanged: (_) {},
                  batchMode: true,
                  onBatchModeChanged: (_) {},
                  onSearchChanged: queries.add,
                  groupFilter: OutlinedButton.icon(
                    key: const Key('groupToolbarControl'),
                    onPressed: () => groupTaps++,
                    icon: const Icon(Icons.folder_outlined, size: 16),
                    label: Text(
                      language == 'zh' ? '全部分组' : 'All groups',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            for (final key in [
              'deviceListSearch',
              'groupToolbarControl',
              'deviceView-list',
              'deviceBatchManage',
            ]) {
              final rect = tester.getRect(find.byKey(Key(key)));
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(width));
            }
            final search = tester.getRect(
              find.byKey(const Key('deviceListSearch')),
            );
            final group = tester.getRect(
              find.byKey(const Key('groupToolbarControl')),
            );
            if (width == 1200 && scale == 1) {
              expect(
                find.byKey(const Key('deviceToolbarSingleRow')),
                findsOneWidget,
              );
            }
            if (find
                .byKey(const Key('deviceToolbarSingleRow'))
                .evaluate()
                .isNotEmpty) {
              final views = tester.getRect(
                find.byKey(const Key('deviceView-wall')),
              );
              expect(search.right, lessThan(group.left));
              expect(group.right, lessThan(views.left));
              expect(search.center.dy, closeTo(group.center.dy, 2));
              expect(search.width, greaterThanOrEqualTo(160));
            } else if (width <= 360 && scale == 1.6) {
              expect(group.top, greaterThan(search.bottom));
              expect(search.width, width);
              expect(group.width, width);
            }
            await tester.tap(find.byKey(const Key('groupToolbarControl')));
            await tester.enterText(
              find.byKey(const Key('deviceListSearch')),
              'Pixel-$width-$scale',
            );
            await tester.pump();
            expect(queries.last, 'Pixel-$width-$scale');
            expect(tester.takeException(), isNull);
          }
        }
        expect(groupTaps, 10);
      });
    }
  }
}

Widget _host({
  required Widget child,
  required String language,
  required Brightness brightness,
  required double scale,
}) => MaterialApp(
  theme: buildAppTheme(brightness),
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  builder: (context, content) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: content!,
  ),
  home: Scaffold(
    body: Align(alignment: Alignment.topCenter, child: child),
  ),
);
