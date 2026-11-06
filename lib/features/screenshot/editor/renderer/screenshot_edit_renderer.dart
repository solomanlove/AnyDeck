import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model/screenshot_edit.dart';

/// 预览与 PNG 导出共用的标注绘制器，所有操作均以未旋转的原图像素为单位。
class ScreenshotEditRenderer {
  const ScreenshotEditRenderer._();

  static const mosaicBlockSize = 18;

  /// 为当前底图生成一次低分辨率纹理，涂抹时以最近邻放大，避免逐帧读取像素。
  static Future<ui.Image> createMosaic(ui.Image source) async {
    final width = math.max(1, (source.width / mosaicBlockSize).ceil());
    final height = math.max(1, (source.height / mosaicBlockSize).ceil());
    final recorder = ui.PictureRecorder();
    ui.Picture? picture;
    try {
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        source,
        _imageRect(source),
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..filterQuality = FilterQuality.low,
      );
      picture = recorder.endRecording();
      return await picture.toImage(width, height);
    } finally {
      picture?.dispose();
      if (recorder.isRecording) recorder.endRecording().dispose();
    }
  }

  /// 仅绘制标注层；source 提供原图边界，mosaicImage 是 createMosaic 的缓存结果。
  static void paint(
    Canvas canvas,
    ui.Image source,
    Iterable<ScreenshotEditMark> marks, {
    ui.Image? mosaicImage,
  }) {
    canvas.save();
    canvas.clipRect(_imageRect(source));
    for (final mark in marks) {
      if (mark.points.isEmpty) continue;
      final brush = Paint()
        ..color = mark.color
        ..strokeWidth = mark.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      switch (mark.tool) {
        case ScreenshotEditTool.pan:
          break;
        case ScreenshotEditTool.rectangle:
          canvas.drawRect(mark.rect, brush);
        case ScreenshotEditTool.ellipse:
          canvas.drawOval(mark.rect, brush);
        case ScreenshotEditTool.cover:
          canvas.drawRect(
            mark.rect,
            brush
              ..style = PaintingStyle.fill
              ..color = mark.color.withValues(alpha: 1),
          );
        case ScreenshotEditTool.pen:
          if (mark.points.length == 1) {
            canvas.drawCircle(
              mark.points.first,
              mark.width / 2,
              brush..style = PaintingStyle.fill,
            );
          } else {
            canvas.drawPath(_strokePath(mark.points), brush);
          }
        case ScreenshotEditTool.mosaic:
          if (mosaicImage == null) continue;
          canvas.save();
          canvas.clipPath(_strokeArea(mark), doAntiAlias: false);
          canvas.drawImageRect(
            mosaicImage,
            _imageRect(mosaicImage),
            _imageRect(source),
            Paint()..filterQuality = FilterQuality.none,
          );
          canvas.restore();
      }
    }
    canvas.restore();
  }

  /// 合成当前底图和操作列表，输出原始分辨率 PNG；成功后由调用方释放 result.image。
  static Future<ScreenshotEditResult> render(
    ui.Image source,
    List<ScreenshotEditMark> marks, {
    ui.Image? mosaicImage,
  }) async {
    ui.Image? ownedMosaic;
    ui.PictureRecorder? recorder;
    ui.Picture? picture;
    ui.Image? image;
    try {
      if (mosaicImage == null &&
          marks.any((mark) => mark.tool == ScreenshotEditTool.mosaic)) {
        ownedMosaic = await createMosaic(source);
      }
      recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(source, Offset.zero, Paint());
      paint(canvas, source, marks, mosaicImage: mosaicImage ?? ownedMosaic);
      picture = recorder.endRecording();
      image = await picture.toImage(source.width, source.height);
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null) throw StateError('PNG encoding returned no data');
      return ScreenshotEditResult(
        bytes: encoded.buffer.asUint8List(
          encoded.offsetInBytes,
          encoded.lengthInBytes,
        ),
        image: image,
      );
    } catch (_) {
      image?.dispose();
      rethrow;
    } finally {
      picture?.dispose();
      if (recorder?.isRecording == true) recorder!.endRecording().dispose();
      ownedMosaic?.dispose();
    }
  }

  static Rect _imageRect(ui.Image image) =>
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  static Path _strokePath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }

  /// 以圆端点和连接四边形组成填充蒙版，使马赛克只覆盖笔迹而不覆盖包围盒。
  static Path _strokeArea(ScreenshotEditMark mark) {
    final path = Path();
    final radius = mark.width / 2;
    for (var i = 0; i < mark.points.length; i++) {
      final point = mark.points[i];
      path.addOval(Rect.fromCircle(center: point, radius: radius));
      if (i == 0) continue;
      final previous = mark.points[i - 1];
      final delta = point - previous;
      if (delta.distanceSquared == 0) continue;
      final normal = Offset(-delta.dy, delta.dx) / delta.distance * radius;
      path.addPolygon([
        previous - normal,
        point - normal,
        point + normal,
        previous + normal,
      ], true);
    }
    return path;
  }
}
