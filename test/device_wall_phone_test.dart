import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_asset_image.dart';
import 'package:any_deck/features/devices/widgets/device_wall_phone.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通过实际绘制像素检查截图裁剪与品牌封面，避免只检查 Widget 参数。
void main() {
  for (final wide in [true, false]) {
    testWidgets('${wide ? '宽' : '高'}比例截图居中铺满手机屏幕，不出现留白或偏向边缘', (tester) async {
      final screenshot = (await tester.runAsync(() => _centeredPng(wide)))!;
      final boundary = GlobalKey();
      await tester.pumpWidget(_host(boundary, screenshot: screenshot));
      await _waitForImage(tester);

      final pixels = await _pixels(tester, boundary);
      // 这四个位置避开圆角与摄像头，靠近屏幕四边，均应显示原图中心绿色。
      for (final point in const [
        Offset(20, 30),
        Offset(100, 30),
        Offset(20, 215),
        Offset(100, 215),
      ]) {
        expect(
          pixels.at(point).toARGB32(),
          Colors.green.toARGB32(),
          reason: '采样点 $point 存在留白或裁剪未居中',
        );
      }
      expect(find.text('设备已就绪'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} 各品牌在线及离线封面保持白底且文字清晰', (tester) async {
      const brands = {
        'Samsung': AppIcons.samsung,
        'Huawei': AppIcons.huawei,
        'HONOR': AppIcons.honor,
        'Xiaomi': AppIcons.xiaomiSvg,
        'Android': AppIcons.androidDefaultAppIcon,
      };
      for (final brand in brands.entries) {
        for (final online in [true, false]) {
          final boundary = GlobalKey();
          await tester.pumpWidget(
            _host(
              boundary,
              brightness: brightness,
              brand: brand.key,
              logoAsset: brand.value,
              online: online,
            ),
          );
          await tester.pumpAndSettle();

          final pixels = await _pixels(tester, boundary);
          for (final point in const [Offset(20, 30), Offset(100, 190)]) {
            expect(
              pixels.at(point),
              Colors.white,
              reason: '${brand.key} 封面应为白底',
            );
          }
          final texts = tester.widgetList<Text>(find.byType(Text));
          expect(texts, isNotEmpty);
          for (final text in texts) {
            final foreground = text.style!.color!;
            final contrast = 1.05 / (foreground.computeLuminance() + .05);
            expect(contrast, greaterThanOrEqualTo(4.5), reason: '白底封面文字对比度不足');
          }
          expect(
            tester.widget<AppAssetImage>(find.byType(AppAssetImage)).assetName,
            brand.value,
          );
          expect(find.text('当前屏幕快照'), online ? findsOneWidget : findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('${brightness.name} 截图解码失败回退白色品牌封面', (tester) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _host(
          boundary,
          brightness: brightness,
          screenshot: Uint8List.fromList([0, 1, 2, 3]),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();

      expect(find.text('设备已就绪'), findsOneWidget);
      expect(find.byType(AppAssetImage), findsOneWidget);
      final pixels = await _pixels(tester, boundary);
      expect(pixels.at(const Offset(20, 30)), Colors.white);
      expect(pixels.at(const Offset(100, 190)), Colors.white);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('设备离线后隐藏已显示的历史截图并恢复白色封面', (tester) async {
    final screenshot = (await tester.runAsync(() => _centeredPng(true)))!;
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(boundary, screenshot: screenshot));
    await _waitForImage(tester);
    expect(find.text('设备未连接'), findsNothing);
    final onlinePixels = await _pixels(tester, boundary);
    expect(
      onlinePixels.at(const Offset(20, 30)).toARGB32(),
      Colors.green.toARGB32(),
    );

    await tester.pumpWidget(
      _host(boundary, online: false, screenshot: screenshot),
    );
    await tester.pumpAndSettle();
    expect(find.text('设备未连接'), findsOneWidget);
    expect(find.byType(AppAssetImage), findsOneWidget);
    expect(find.byType(RawImage), findsNothing, reason: 'SVG 封面下不应残留截图');
    final offlinePixels = await _pixels(tester, boundary);
    expect(offlinePixels.at(const Offset(20, 30)), Colors.white);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(
  GlobalKey boundary, {
  Brightness brightness = Brightness.light,
  String brand = 'Xiaomi',
  String logoAsset = AppIcons.xiaomiSvg,
  bool online = true,
  Uint8List? screenshot,
}) => MaterialApp(
  theme: buildAppTheme(brightness),
  themeAnimationDuration: Duration.zero,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: boundary,
        child: DeviceWallPhone(
          width: 120,
          online: online,
          brand: brand,
          logoAsset: logoAsset,
          title: online ? '设备已就绪' : '设备未连接',
          hint: '当前屏幕快照',
          semanticLabel: '设备预览',
          screenshot: screenshot,
        ),
      ),
    ),
  ),
);

/// 图片中间绿色、两端红蓝，用实际可见颜色区分居中裁剪和边缘对齐。
Future<Uint8List> _centeredPng(bool wide) async {
  final size = wide ? const Size(600, 240) : const Size(120, 960);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.red, BlendMode.src);
  final center = wide
      ? Rect.fromLTWH(size.width * .4, 0, size.width * .2, size.height)
      : Rect.fromLTWH(0, size.height / 3, size.width, size.height / 3);
  canvas.drawRect(center, Paint()..color = Colors.green);
  canvas.drawRect(
    wide
        ? Rect.fromLTWH(size.width * .6, 0, size.width * .4, size.height)
        : Rect.fromLTWH(0, size.height * 2 / 3, size.width, size.height / 3),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  picture.dispose();
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// 等待真实图片解码完成，确保后续像素来自截图而非加载中的空表面。
Future<void> _waitForImage(WidgetTester tester) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    final images = tester.widgetList<RawImage>(find.byType(RawImage));
    if (images.any((image) => image.image != null)) return;
  }
  fail('截图未完成解码');
}

/// 按 1:1 逻辑像素抓取手机 Widget 的真实绘制结果，并及时释放 ui.Image。
Future<_Pixels> _pixels(WidgetTester tester, GlobalKey boundary) async =>
    (await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      try {
        return _Pixels(
          image.width,
          (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List(),
        );
      } finally {
        image.dispose();
      }
    }))!;

/// 小型像素读取器，所有坐标均为手机左上角起算的逻辑坐标。
class _Pixels {
  const _Pixels(this.width, this.bytes);

  final int width;
  final Uint8List bytes;

  Color at(Offset point) {
    final offset = (point.dy.toInt() * width + point.dx.toInt()) * 4;
    return Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
  }
}
