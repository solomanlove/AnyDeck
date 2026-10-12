import 'package:any_deck/core/ios/ios_control_provider.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/features/control/ios_mirror_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('USB 画面点击按最新 WDA 几何转换为 iOS point', (tester) async {
    const udid = '7921870d9d17013e2a92b936f161c7fc6de1af29';
    final calls = <(String, Map<String, dynamic>)>[];
    final container = ProviderContainer(
      overrides: [
        iosControlCallProvider.overrideWithValue((
          device,
          action, [
          args = const {},
        ]) async {
          calls.add((action, args));
          return switch (action) {
            'status' => {'ready': true, 'busy': false},
            'geometry' => {
              'ready': true,
              'width': 375,
              'height': 812,
              'orientation': 'PORTRAIT',
            },
            'tap' => {'ready': true},
            _ => {'ready': true},
          };
        }),
      ],
    );
    container.read(iosUsbFrameProvider(udid).notifier).update({
      'width': 500,
      'height': 1080,
    });

    await tester.binding.setSurfaceSize(const Size(500, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: IosMirrorViewer(deviceId: udid, port: 1)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    calls.clear();

    await tester.tapAt(const Offset(250, 540));
    await tester.pump();

    final tap = calls.singleWhere((call) => call.$1 == 'tap');
    expect(tap.$2['x'], closeTo(187.5, 0.01));
    expect(tap.$2['y'], closeTo(406, 0.01));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  });
}
