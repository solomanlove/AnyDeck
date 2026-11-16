import 'package:any_deck/app/window/mirror/mirror_window_frame_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 窗口位置与尺寸的有效范围不同，贴边或越过原点不能丢弃整个比例适配。
void main() {
  test('同方向收敛保留合法的零纵坐标', () {
    final frame = MirrorWindowFrameAdapter.calculateFittedFrame(
      frame: const Rect.fromLTWH(0, 0, 500, 600),
      aspectRatio: 0.6,
      viewerW: 468,
      viewerH: 570,
    );
    expect(frame, isNotNull);
    expect(frame!.top, 0);
    expect(frame.left, 63);
    expect((frame.width - 32) / (frame.height - 30), closeTo(0.6, 0.0001));
  });

  test('同方向收敛保留合法的零横坐标', () {
    final frame = MirrorWindowFrameAdapter.calculateFittedFrame(
      frame: const Rect.fromLTWH(0, 0, 500, 600),
      aspectRatio: 0.9,
      viewerW: 468,
      viewerH: 570,
    );
    expect(frame, isNotNull);
    expect(frame!.left, 0);
    expect(frame.top, 25);
    expect((frame.width - 32) / (frame.height - 30), closeTo(0.9, 0.0001));
  });

  test('负屏幕坐标仍计算目标尺寸并使用既有原点边界', () {
    final frame = MirrorWindowFrameAdapter.calculateFittedFrame(
      frame: const Rect.fromLTWH(-300, -200, 500, 600),
      aspectRatio: 0.6,
      viewerW: 468,
      viewerH: 570,
    );
    expect(frame, isNotNull);
    expect(frame!.left, 0);
    expect(frame.top, 0);
    expect(frame.width, 374);
    expect(frame.height, 600);
  });

  test('横屏切换长竖屏越过原点时仍扩展窗口并贴边', () {
    const aspect = 682 / 1080;
    final frame = MirrorWindowFrameAdapter.calculateFittedFrame(
      frame: const Rect.fromLTWH(200, 20, 802, 611),
      aspectRatio: aspect,
      viewerW: 770,
      viewerH: 581,
    );
    expect(frame, isNotNull);
    expect(frame!.top, 0);
    expect(frame.height, 800);
    expect(frame.width, closeTo(770 * aspect + 32, 0.0001));
    expect((frame.width - 32) / (frame.height - 30), closeTo(aspect, 0.0001));
  });

  test('非有限坐标仍拒绝适配', () {
    for (final coordinate in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final frame = MirrorWindowFrameAdapter.calculateFittedFrame(
        frame: Rect.fromLTWH(coordinate, 0, 500, 600),
        aspectRatio: 0.6,
        viewerW: 468,
        viewerH: 570,
      );
      expect(frame, isNull);
    }
  });
}
