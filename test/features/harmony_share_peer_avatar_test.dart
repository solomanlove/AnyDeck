import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_peer_avatar.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_stage.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_drop_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final peer = ShareCorePeer(
    address: InternetAddress('192.168.1.2'),
    port: 44800,
    name: 'nova 12 Ultra',
  );
  ShareSendBatch batch(
    ShareSendStatus status, {
    String id = 'active',
    int bytes = 0,
  }) => ShareSendBatch(
    id: id,
    transferredBytes: bytes,
    items: [
      for (var i = 0; i < 3; i++)
        ShareSendItem(
          id: '$id-$i',
          peer: peer,
          status: status,
          file: ShareSendFile(
            file: File('/synthetic/$i'),
            bytes: 100,
            modified: DateTime(2026),
          ),
        ),
    ],
  );
  Widget host(
    Widget child, {
    Brightness brightness = Brightness.light,
    String language = 'zh',
    double scale = 1,
  }) => MaterialApp(
    theme: buildAppTheme(brightness),
    locale: Locale(language),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(body: child),
    ),
  );
  Widget stage({
    List<ShareCorePeer>? peers,
    List<ShareSendBatch> batches = const [],
    bool enabled = true,
    bool busy = false,
    bool unavailable = false,
    bool cancelling = false,
    void Function(ShareCorePeer)? onPick,
    void Function(ShareCorePeer, List<File>)? onDrop,
  }) => HarmonyShareStage(
    peers: peers ?? [peer],
    batches: batches,
    header: const SizedBox(height: 88),
    footer: const SizedBox(height: 100),
    enabled: enabled,
    busy: busy,
    unavailable: unavailable,
    activeBatchId: 'active',
    cancelling: cancelling,
    onPick: onPick ?? (_) {},
    onDrop: onDrop ?? (_, _) {},
    onInvalidDrop: () {},
  );

  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('无设备/单设备/多设备/发送批次不改变背景高度 ${brightness.name} $language', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(480, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          host(
            stage(peers: []),
            brightness: brightness,
            language: language,
          ),
        );
        final initial = tester.getRect(find.byType(HarmonyShareStage));
        final content = tester.getRect(
          find.byKey(const ValueKey('harmony-share-discovery-content')),
        );
        expect(
          find.text(language == 'zh' ? '正在搜索设备…' : 'Searching for devices…'),
          findsOneWidget,
        );
        expect(find.byType(FilledButton), findsNothing);
        for (final widget in [
          stage(),
          stage(
            peers: [
              for (var i = 0; i < 20; i++)
                ShareCorePeer(
                  address: InternetAddress('192.168.1.${i + 2}'),
                  port: 44800,
                  name: 'Phone $i',
                ),
            ],
          ),
          stage(
            batches: [
              batch(ShareSendStatus.preparing),
              batch(ShareSendStatus.queued, id: 'next'),
            ],
          ),
          stage(batches: [batch(ShareSendStatus.transferring, bytes: 150)]),
          stage(batches: [batch(ShareSendStatus.succeeded, bytes: 300)]),
        ]) {
          await tester.pumpWidget(
            host(widget, brightness: brightness, language: language),
          );
          expect(tester.getRect(find.byType(HarmonyShareStage)), initial);
          expect(
            tester.getRect(
              find.byKey(const ValueKey('harmony-share-discovery-content')),
            ),
            content,
          );
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('状态区分搜索、关闭、服务失败和收发忙碌', (tester) async {
    for (final entry in {
      '接收已关闭': stage(peers: [], enabled: false),
      '服务暂不可用': stage(peers: [], unavailable: true),
      '等待手机确认或传输完成': stage(peers: [], busy: true),
    }.entries) {
      await tester.pumpWidget(host(entry.value));
      expect(find.text(entry.key), findsOneWidget);
      expect(find.text('正在搜索设备…'), findsNothing);
    }
  });

  testWidgets('头像呈现待接收、真实进度、确认、成功与失败终态', (tester) async {
    for (final entry in {
      '待接收': batch(ShareSendStatus.preparing),
      '发送中': batch(ShareSendStatus.transferring, bytes: 150),
      '确认中': batch(ShareSendStatus.transferring, bytes: 300),
      '已发送': batch(ShareSendStatus.succeeded, bytes: 300),
      '发送失败': batch(ShareSendStatus.failed, bytes: 100),
      '已取消': batch(ShareSendStatus.cancelled, bytes: 100),
    }.entries) {
      await tester.pumpWidget(host(stage(batches: [entry.value])));
      expect(find.text(entry.key), findsOneWidget);
      expect(find.text('本批 3 个文件'), findsOneWidget);
      final ring = find.byType(CircularProgressIndicator);
      if (entry.key == '发送中' || entry.key == '确认中') {
        expect(
          tester.widget<CircularProgressIndicator>(ring).value,
          entry.value.transferredBytes / 300,
        );
      } else {
        expect(ring, findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('发送时可继续整组拖放追加下一批，不混入活动批次', (tester) async {
    ShareCorePeer? picked;
    List<File>? dropped;
    await tester.pumpWidget(
      host(
        stage(
          batches: [
            batch(ShareSendStatus.transferring, bytes: 150),
            batch(ShareSendStatus.queued, id: 'next'),
          ],
          onPick: (value) => picked = value,
          onDrop: (_, files) => dropped = files,
        ),
      ),
    );
    expect(find.text('另有 1 批排队'), findsOneWidget);
    await tester.tap(find.text(peer.name));
    expect(picked, same(peer));
    final target = tester.widget<HarmonyShareDropTarget>(
      find.byType(HarmonyShareDropTarget),
    );
    expect(target.enabled, isTrue);
    final files = [File('/synthetic/a'), File('/synthetic/b')];
    target.onDrop(files);
    expect(dropped, same(files));
    expect(find.byType(HarmonyShareDropTarget), findsOneWidget);
  });

  testWidgets('断开后的结果头像保留但禁止使用旧端口选文件或拖放', (tester) async {
    await tester.pumpWidget(
      host(stage(peers: [], batches: [batch(ShareSendStatus.succeeded)])),
    );
    expect(find.text('已发送'), findsOneWidget);
    expect(
      tester
          .widget<HarmonyShareDropTarget>(find.byType(HarmonyShareDropTarget))
          .enabled,
      isFalse,
    );
    final ink = find.descendant(
      of: find.byType(HarmonySharePeerAvatar),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(ink).onTap, isNull);
  });

  testWidgets('窄窗口大字体与长名称可读，设备在区域内滚动', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final peers = [
      for (var i = 0; i < 12; i++)
        ShareCorePeer(
          address: InternetAddress('192.168.1.${i + 2}'),
          port: 44800,
          name: '很长的设备名称用于检查布局 $i',
        ),
    ];
    await tester.pumpWidget(host(stage(peers: peers), scale: 2));
    await tester.drag(find.byType(GridView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(HarmonyShareStage)).height, 584);
  });
}
