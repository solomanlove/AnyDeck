import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/window/mirror/widget/mirror_app_quick_actions_dialog.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/scrcpy/fusion_mode_preference.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用真实文件覆盖图标存在性检查、图片解码与失败回退，不调用设备服务。
void main() {
  for (final icon in ['none', 'missing', 'valid', 'corrupt']) {
    testWidgets('投屏快捷操作图标 $icon 保留头栏与关闭交互', (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final directory = Directory.systemTemp.createTempSync('anydeck-icon-');
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        directory.deleteSync(recursive: true);
      });
      final file = File('${directory.path}/icon.png');
      if (icon == 'valid') {
        file.writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
      } else if (icon == 'corrupt') {
        file.writeAsStringSync('invalid image bytes');
      }
      final package = AdbPackage(
        name: 'com.anydeck.fixture',
        label: 'Fixture App',
        versionName: '1.2.3',
        iconLocalPath: icon == 'none' ? null : file.path,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceFusionModeProvider('fixture-device').overrideWith(
              (ref) async => const FusionModeStatus(FusionModeState.disabled),
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showMirrorAppQuickActionsDialog(
                    context: context,
                    ref: ref,
                    deviceId: 'fixture-device',
                    package: package,
                  ),
                  child: const Text('打开快捷操作'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('打开快捷操作'));
        await tester.pump();
        if (icon == 'valid' || icon == 'corrupt') {
          final image = tester.widget<Image>(find.byType(Image));
          expect((image.image as FileImage).file.path, file.path);
          await _waitForImage(image.image);
        }
      });
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Fixture App'), findsOneWidget);
      expect(find.text(package.name), findsOneWidget);
      expect(find.text('v1.2.3'), findsOneWidget);
      if (icon == 'valid') {
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
        expect(find.byIcon(CupertinoIcons.app_badge), findsNothing);
      } else {
        expect(find.byIcon(CupertinoIcons.app_badge), findsOneWidget);
        expect(find.byType(RawImage), findsNothing);
        expect(
          find.byType(Image),
          icon == 'corrupt' ? findsOneWidget : findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(CupertinoIcons.xmark));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

/// 在真实异步区域等待文件 IO 与 codec 完成，再推进 Widget 的图片状态。
Future<void> _waitForImage(ImageProvider image) async {
  final completer = Completer<void>();
  final stream = image.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener(
    (image, _) {
      image.dispose();
      if (!completer.isCompleted) completer.complete();
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!completer.isCompleted) completer.complete();
    },
  );
  stream.addListener(listener);
  try {
    await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    stream.removeListener(listener);
  }
}
