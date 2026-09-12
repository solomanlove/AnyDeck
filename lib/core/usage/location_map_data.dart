import 'package:latlong2/latlong.dart';

import 'companion_history.dart';

/// 将已同步 WGS84 记录整理为地图点和连续轨迹，不修改原始坐标。
class LocationMapData {
  LocationMapData(List<LocationRecord> records) {
    final newest = records.toList()
      ..sort((a, b) => b.capturedAtMs.compareTo(a.capturedAtMs));
    points = newest.take(1000).toList().reversed.toList();
    segments = [];
    var segment = <LatLng>[];
    LocationRecord? previous;
    for (final point in points) {
      if (point.mock ||
          (previous != null &&
              (point.capturedAtMs - previous.capturedAtMs > 30 * 60000 ||
                  (point.longitude - previous.longitude).abs() >= 180))) {
        if (segment.length > 1) segments.add(segment);
        segment = [];
      }
      if (!point.mock) segment.add(coordinate(point));
      previous = point;
    }
    if (segment.length > 1) segments.add(segment);
  }

  late final List<LocationRecord> points;
  late final List<List<LatLng>> segments;
  LocationRecord? get latest => points.lastOrNull;
  List<LatLng> get coordinates => points.map(coordinate).toList();

  static LatLng coordinate(LocationRecord point) =>
      LatLng(point.latitude, point.longitude);
}
