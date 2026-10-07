import 'dart:ui';
import 'package:any_deck/core/ios/ios_mirror_coordinates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iPhone 6s pixels map to points with pillarboxing', () {
    const viewport = Size(1000, 667);
    const pixels = Size(750, 1334);
    const points = Size(375, 667);
    expect(
      IosMirrorCoordinates.toPoints(
        const Offset(500, 333.5),
        viewport,
        pixels,
        points,
      ),
      const Offset(187.5, 333.5),
    );
    expect(
      IosMirrorCoordinates.toPoints(
        const Offset(100, 100),
        viewport,
        pixels,
        points,
      ),
      isNull,
    );
    expect(
      IosMirrorCoordinates.toPoints(
        const Offset(687.5, 100),
        viewport,
        pixels,
        points,
      ),
      isNull,
    );
  });
  test('rotation mismatch and invalid dimensions reject input', () {
    expect(
      IosMirrorCoordinates.toPoints(
        const Offset(10, 10),
        const Size(800, 400),
        const Size(1334, 750),
        const Size(375, 667),
      ),
      isNull,
    );
    expect(
      IosMirrorCoordinates.toPoints(
        Offset.zero,
        Size.zero,
        const Size(750, 1334),
        const Size(375, 667),
      ),
      isNull,
    );
  });
  test('landscape letterboxing maps center correctly', () {
    expect(
      IosMirrorCoordinates.toPoints(
        const Offset(400, 400),
        const Size(800, 800),
        const Size(1334, 750),
        const Size(667, 375),
      ),
      const Offset(333.5, 187.5),
    );
  });
}
