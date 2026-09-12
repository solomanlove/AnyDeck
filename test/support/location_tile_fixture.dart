import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// 测试专用内存瓦片，避免 widget 测试访问真实地图服务器。
class FixtureTileProvider extends TileProvider {
  int requests = 0;
  bool disposed = false;
  final _image = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requests++;
    return _image;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
