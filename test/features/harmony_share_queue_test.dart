import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_queue_panel.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_stage.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_drop_target.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final peer = ShareCorePeer(
    address: InternetAddress('192.168.1.3'),
    port: 44800,
    name: 'nova',
  );
  Widget host(
    Widget child, {
    String language = 'zh',
    Brightness brightness = Brightness.light,
  }) => MaterialApp(
    theme: buildAppTheme(brightness),
    locale: Locale(language),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(body: child),
  );
  final drop = DropDoneDetails(
    files: [DropItemFile('/synthetic/a.bin'), DropItemFile('/synthetic/b.bin')],
    localPosition: Offset.zero,
    globalPosition: Offset.zero,
  );

  testWidgets('一次拖入多个文件只触发一次目标确认', (tester) async {
    var calls = 0;
    List<File>? files;
    await tester.pumpWidget(
      host(
        HarmonyShareStage(
          peers: [peer],
          enabled: true,
          busy: false,
          onPick: (_) {},
          onDrop: (target, selection) {
            expect(target, same(peer));
            calls++;
            files = selection;
          },
          onInvalidDrop: () {},
        ),
      ),
    );
    tester.widgetList<DropTarget>(find.byType(DropTarget)).first.onDragDone!(
      drop,
    );
    expect(calls, 1);
    expect(files!.map((file) => file.path), [
      '/synthetic/a.bin',
      '/synthetic/b.bin',
    ]);
  });

  testWidgets('多设备中央拖放不猜测目标', (tester) async {
    var invalid = false;
    var sent = false;
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: HarmonyShareStage(
            peers: [
              peer,
              ShareCorePeer(
                address: InternetAddress('192.168.1.4'),
                port: 44800,
                name: 'other',
              ),
            ],
            enabled: true,
            busy: false,
            onPick: (_) {},
            onDrop: (_, _) => sent = true,
            onInvalidDrop: () => invalid = true,
          ),
        ),
      ),
    );
    tester.widgetList<DropTarget>(find.byType(DropTarget)).last.onDragDone!(
      drop,
    );
    expect(sent, isFalse);
    expect(invalid, isTrue);
  });

  testWidgets('拖入高亮仅更新当前区域，禁用后不接受拖放', (tester) async {
    var sent = false;
    Widget target(bool enabled) => host(
      HarmonyShareDropTarget(
        enabled: enabled,
        onDrop: (_) => sent = true,
        child: const SizedBox(width: 100, height: 100),
      ),
    );
    await tester.pumpWidget(target(true));
    tester.widget<DropTarget>(find.byType(DropTarget)).onDragEntered!(
      DropEventDetails(
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();
    final container = find.descendant(
      of: find.byType(HarmonyShareDropTarget),
      matching: find.byType(Container),
    );
    final decoration =
        tester.widget<Container>(container).foregroundDecoration!
            as BoxDecoration;
    expect(
      (decoration.border! as Border).top.color,
      buildAppTheme(Brightness.light).colorScheme.primary,
    );
    await tester.pumpWidget(target(false));
    expect(tester.widget<DropTarget>(find.byType(DropTarget)).enable, isFalse);
    tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(drop);
    expect(sent, isFalse);
  });

  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('队列窄窗口主题与语言 ${brightness.name} $language', (tester) async {
        tester.view.physicalSize = const Size(480, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? cancelled;
        final items = [
          for (var index = 0; index < 100; index++)
            ShareSendItem(
              id: '$index',
              peer: peer,
              file: ShareSendFile(
                file: File('/synthetic/file-$index.bin'),
                bytes: 100,
                modified: DateTime(2026),
              ),
            ),
        ];
        await tester.pumpWidget(
          host(
            HarmonyShareQueuePanel(
              items: items,
              running: true,
              onCancel: (id) => cancelled = id,
              onCancelAll: () {},
              onClear: () {},
            ),
            brightness: brightness,
            language: language,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('file-0.bin'), findsOneWidget);
        expect(find.text('file-99.bin'), findsNothing);
        await tester.tap(
          find.byTooltip(language == 'zh' ? '取消此文件' : 'Cancel this file').first,
        );
        expect(cancelled, '0');
      });
    }
  }
}
