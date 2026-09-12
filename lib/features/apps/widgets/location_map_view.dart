import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/usage/companion_history.dart';
import '../../../core/usage/location_map_data.dart';

/// 瓦片提供器工厂：每张地图独占连接生命周期，测试可注入内存瓦片。
final locationTileProviderFactoryProvider = Provider<TileProvider Function()>(
  (ref) =>
      () => NetworkTileProvider(
        headers: {'User-Agent': 'AnyDeck/1.0 (Desktop Location History)'},
        attemptDecodeOfHttpErrorResponses: false,
      ),
);

/// 内嵌 WGS84 历史地图；points 为本地记录，底图按当前视口联网加载。
/// 持有并释放 MapController 和瓦片重试流，数据改变时重新框选轨迹。
class LocationMapView extends ConsumerStatefulWidget {
  const LocationMapView({super.key, required this.points});
  final List<LocationRecord> points;

  @override
  ConsumerState<LocationMapView> createState() => _LocationMapViewState();
}

class _LocationMapViewState extends ConsumerState<LocationMapView> {
  final _map = MapController();
  final _reset = StreamController<void>.broadcast();
  late final TileProvider _tiles;
  late LocationMapData _data;
  bool _tileError = false;
  bool _errorScheduled = false;

  @override
  void initState() {
    super.initState();
    _tiles = ref.read(locationTileProviderFactoryProvider)();
    _data = LocationMapData(widget.points);
  }

  @override
  void didUpdateWidget(covariant LocationMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.points, widget.points)) {
      _data = LocationMapData(widget.points);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit();
      });
    }
  }

  CameraFit get _fitBounds => CameraFit.coordinates(
    coordinates: _data.coordinates,
    padding: const EdgeInsets.all(48),
    maxZoom: 17,
    minZoom: 2,
  );

  void _fit() {
    if (_data.points.isNotEmpty) _map.fitCamera(_fitBounds);
  }

  void _zoom(double delta) {
    _map.move(_map.camera.center, (_map.camera.zoom + delta).clamp(2, 19));
  }

  void _onTileError(TileImage tile, Object error, StackTrace? stack) {
    if (_tileError || _errorScheduled) return;
    _errorScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _errorScheduled = false;
      if (mounted) setState(() => _tileError = true);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _attribution() async {
    try {
      await ref
          .read(webDebugServiceProvider)
          .openBrowser('https://www.openstreetmap.org/copyright');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('locationMapFailed'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = _data.latest;
    if (latest == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final latestColor = latest.mock ? colors.error : colors.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: LocationMapData.coordinate(latest),
              initialCameraFit: _fitBounds,
              minZoom: 2,
              maxZoom: 19,
              backgroundColor: colors.surfaceContainerHighest,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.anydeck.desktop',
                tileProvider: _tiles,
                maxNativeZoom: 19,
                panBuffer: 0,
                reset: _reset.stream,
                evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
                errorTileCallback: _onTileError,
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LocationMapData.coordinate(latest),
                    radius: latest.accuracyMeters,
                    useRadiusInMeter: true,
                    color: latestColor.withValues(alpha: 0.12),
                    borderColor: latestColor.withValues(alpha: 0.5),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  for (final segment in _data.segments)
                    Polyline(
                      points: segment,
                      color: colors.primary,
                      strokeWidth: 3,
                    ),
                ],
              ),
              CircleLayer(
                circles: [
                  for (final point in _data.points)
                    CircleMarker(
                      point: LocationMapData.coordinate(point),
                      radius: 4,
                      color: point.mock ? colors.error : colors.primary,
                      borderColor: colors.surface,
                      borderStrokeWidth: 1,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LocationMapData.coordinate(latest),
                    width: 36,
                    height: 42,
                    alignment: Alignment.topCenter,
                    child: Tooltip(
                      message: context.l10n.t('locationMapLatest'),
                      child: Icon(
                        Icons.location_pin,
                        size: 36,
                        color: latestColor,
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Material(
                  color: colors.surface,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.all(4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _attribution,
                    child: Text(
                      '© ${context.l10n.t('locationMapAttribution')}',
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                children: [
                  IconButton(
                    tooltip: context.l10n.t('locationMapZoomIn'),
                    onPressed: () => _zoom(1),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: context.l10n.t('locationMapZoomOut'),
                    onPressed: () => _zoom(-1),
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    tooltip: context.l10n.t('locationMapFit'),
                    onPressed: _fit,
                    icon: const Icon(Icons.fit_screen),
                  ),
                ],
              ),
            ),
          ),
          if (_tileError)
            Positioned(
              top: 8,
              left: 8,
              right: 64,
              child: Material(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        context.l10n.t('locationTilesFailed'),
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _tileError = false);
                          _reset.add(null);
                        },
                        child: Text(context.l10n.t('locationMapRetry')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _map.dispose();
    _reset.close();
    // TileLayer 负责释放其 TileProvider，包括在途网络请求。
    super.dispose();
  }
}
