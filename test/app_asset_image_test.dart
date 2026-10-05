import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/app/widget/app_asset_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用真实资源验证矢量解码、位图兼容和异步加载失败的回退。
void main() {
  for (final asset in ['assets/brand/app_tray_icon.svg', AppIcons.apple]) {
    testWidgets('loads $asset without decoding errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: AppAssetImage(asset, width: 32, height: 32)),
        ),
      );
      await tester.runAsync(() async {
        await tester.pumpAndSettle();
      });
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(tester.getSize(find.byType(AppAssetImage)), const Size(32, 32));
    });
  }

  for (final extension in ['svg', 'png']) {
    testWidgets('missing $extension keeps image bounds and shows fallback', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: AppAssetImage(
              'assets/brand/missing.$extension',
              width: 32,
              height: 32,
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.pumpAndSettle();
      });
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(tester.getSize(find.byType(AppAssetImage)), const Size(32, 32));
    });
  }
}
