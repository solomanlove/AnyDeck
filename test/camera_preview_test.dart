import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/embedded_camera_backend.dart';
import 'package:any_deck/features/apps/controller/camera_preview_controller.dart';
import 'package:any_deck/features/apps/widgets/camera_preview_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class PreviewBackendFake implements CameraBackend {
  int starts = 0;
  int stops = 0;
  bool cancelled = false;
  Completer<int>? pending;
  final exit = Completer<int>();
  @override
  Future<int> start() async {
    starts++;
    return pending == null ? 77 : pending!.future;
  }

  @override
  Future<Map<String, int>?> videoSize() async => {'width': 1280, 'height': 720};
  @override
  Future<int> get exited => exit.future;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    cancel();
  }
}

void main() {
  test('启动途中停止，迟到结果不会恢复纹理', () async {
    final backend = PreviewBackendFake()..pending = Completer<int>();
    final container = ProviderContainer(
      overrides: [
        deviceOnlineProvider('phone').overrideWith((ref) => true),
        cameraBackendFactoryProvider.overrideWithValue((_, _) => backend),
      ],
    );
    addTearDown(container.dispose);
    container.listen(cameraPreviewProvider('phone'), (_, _) {});
    final controller = container.read(cameraPreviewProvider('phone').notifier);
    final starting = controller.start();
    await controller.stop();
    backend.pending!.complete(77);
    await starting;
    expect(container.read(cameraPreviewProvider('phone')).textureId, isNull);
    expect(backend.cancelled, true);
    expect(backend.stops, greaterThanOrEqualTo(1));
  });

  test('流结束后清理纹理，回到停止状态', () async {
    final backend = PreviewBackendFake();
    final container = ProviderContainer(
      overrides: [
        deviceOnlineProvider('phone').overrideWith((ref) => true),
        cameraBackendFactoryProvider.overrideWithValue((_, _) => backend),
      ],
    );
    addTearDown(container.dispose);
    container.listen(cameraPreviewProvider('phone'), (_, _) {});
    await container.read(cameraPreviewProvider('phone').notifier).start();
    expect(container.read(cameraPreviewProvider('phone')).textureId, 77);
    backend.exit.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(cameraPreviewProvider('phone')).textureId, isNull);
    expect(
      container.read(cameraPreviewProvider('phone')).messageKey,
      'cameraDisconnected',
    );
  });

  for (final locale in ['zh', 'en']) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('摄像头仅点击后启动，显示内嵌 Texture，移除即停止 $locale $brightness', (
        tester,
      ) async {
        final backend = PreviewBackendFake();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              deviceOnlineProvider('phone').overrideWith((ref) => true),
              cameraBackendFactoryProvider.overrideWithValue((_, _) => backend),
            ],
            child: MaterialApp(
              locale: Locale(locale),
              theme: ThemeData(brightness: brightness),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Scaffold(
                body: SizedBox(
                  width: 620,
                  height: 400,
                  child: CameraPreviewView(deviceId: 'phone'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(backend.starts, 0);
        await tester.tap(find.text(locale == 'zh' ? '开始预览' : 'Start preview'));
        await tester.pumpAndSettle();
        expect(tester.widget<Texture>(find.byType(Texture)).textureId, 77);
        expect(backend.starts, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(backend.cancelled, true);
        expect(backend.stops, greaterThanOrEqualTo(1));
      });
    }
  }
}
