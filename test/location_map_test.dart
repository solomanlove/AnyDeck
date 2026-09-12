import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/usage/companion_history.dart';
import 'package:any_deck/core/usage/location_map_data.dart';
import 'package:any_deck/features/apps/widgets/location_map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/location_tile_fixture.dart';

class _FailedTile extends Fake implements TileImage {}

/// 固定坐标仅验证映射，不使用用户实际位置。
LocationRecord point(
  int minute, {
  double latitude = 31.2,
  double longitude = 121.5,
  bool mock = false,
}) => LocationRecord.fromJson({
  'latitude': latitude,
  'longitude': longitude,
  'accuracyMeters': 20.0,
  'capturedAtMs': 1700000000000 + minute * 60000,
  'receivedAtMs': 1700000000000 + minute * 60000,
  'provider': 'gps',
  'mock': mock,
  'coordinateSystem': 'WGS84',
});

void main() {
  test('WGS84 经纬度不互换、不偏移，间隔/模拟位置/日期变更线不跨接', () {
    final data = LocationMapData([
      point(0),
      point(1, longitude: 121.5001),
      point(40),
      point(41, mock: true),
      point(42),
      point(43, longitude: 179.9),
      point(44, longitude: -179.9),
    ]);
    expect(data.coordinates.first.latitude, 31.2);
    expect(data.coordinates.first.longitude, 121.5);
    expect(data.segments.map((segment) => segment.length), [2, 2]);
    expect(data.latest!.longitude, -179.9);
  });

  test('按时间取最近 1000 点，空数据不产生轨迹', () {
    final data = LocationMapData([for (var i = 0; i < 1005; i++) point(i)]);
    expect(data.points.length, 1000);
    expect(data.points.first.capturedAtMs, point(5).capturedAtMs);
    expect(LocationMapData([]).latest, isNull);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('内嵌瓦片、缩放、框选、失败重试和日期更新 $brightness', (tester) async {
      final tiles = FixtureTileProvider();
      final records = ValueNotifier([point(0)]);
      addTearDown(records.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationTileProviderFactoryProvider.overrideWithValue(() => tiles),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            theme: ThemeData(brightness: brightness),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 600,
                  height: 320,
                  child: ValueListenableBuilder<List<LocationRecord>>(
                    valueListenable: records,
                    builder: (context, value, _) =>
                        LocationMapView(points: value),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tiles.requests, greaterThan(0));
      expect(find.text('© OpenStreetMap 贡献者'), findsOneWidget);
      final map = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      expect(map.camera.center.latitude, closeTo(31.2, 0.0001));
      expect(map.camera.center.longitude, closeTo(121.5, 0.0001));
      final zoom = map.camera.zoom;
      await tester.tap(find.byTooltip('放大地图'));
      await tester.pumpAndSettle();
      expect(map.camera.zoom, greaterThan(zoom));
      await tester.tap(find.byTooltip('显示当天全部轨迹'));
      await tester.pumpAndSettle();
      expect(map.camera.zoom, closeTo(zoom, 0.0001));
      final layer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(
        layer.urlTemplate,
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      );
      expect(
        layer.tileProvider.headers['User-Agent'],
        contains('com.anydeck.desktop'),
      );
      // 模拟单块瓦片失败，检查明确提示以及重置后的请求，避免真实联网。
      layer.errorTileCallback!(
        _FailedTile(),
        Exception('tile unavailable'),
        StackTrace.current,
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('部分地图底图加载失败，请检查网络后重试。'), findsOneWidget);
      final requests = tiles.requests;
      await tester.tap(find.text('重试底图'));
      await tester.pumpAndSettle();
      expect(tiles.requests, greaterThan(requests));
      expect(find.text('部分地图底图加载失败，请检查网络后重试。'), findsNothing);
      records.value = [point(1, latitude: 30, longitude: 120)];
      await tester.pumpAndSettle();
      expect(map.camera.center.latitude, closeTo(30, 0.0001));
      expect(map.camera.center.longitude, closeTo(120, 0.0001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(tiles.disposed, isTrue);
    });
  }
}
