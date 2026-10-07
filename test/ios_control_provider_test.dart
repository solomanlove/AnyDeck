import 'dart:async';

import 'package:any_deck/core/ios/ios_control_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用可控 gateway 响应复现旧轮询覆盖启停结果，以及断线后的错误就绪状态。
void main() {
  const geometry = {'ready': true, 'width': 375, 'height': 667};
  final provider = iosControlProvider('phone');

  test('late poll cannot restore ready after stop', () async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        iosControlCallProvider.overrideWithValue((
          udid,
          action, [
          args = const {},
        ]) async {
          if (action == 'status') return geometry;
          if (action == 'geometry') {
            calls++;
            return calls == 1 ? geometry : pending.future;
          }
          return {'ready': false};
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    expect(container.read(provider).ready, true);
    final notifier = container.read(provider.notifier);
    final polling = notifier.refresh();
    await pumpEventQueue();
    await notifier.perform('stop');
    pending.complete(geometry);
    await polling;
    expect(container.read(provider).ready, false);
  });

  test('late failed poll cannot overwrite a successful new start', () async {
    final pending = Completer<Map<String, dynamic>>();
    var first = true;
    final container = ProviderContainer(
      overrides: [
        iosControlCallProvider.overrideWithValue((
          udid,
          action, [
          args = const {},
        ]) async {
          if (action == 'status' && first) {
            first = false;
            return pending.future;
          }
          return geometry;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    await container.read(provider.notifier).perform('start');
    pending.completeError(StateError('iosWdaUnavailable'));
    await pumpEventQueue();
    expect(container.read(provider).ready, true);
    expect(container.read(provider).error, isNull);
  });

  test(
    'failed input uses host status; successful recovery clears old error',
    () async {
      var ready = true;
      final container = ProviderContainer(
        overrides: [
          iosControlCallProvider.overrideWithValue((
            udid,
            action, [
            args = const {},
          ]) async {
            if (action == 'tap') {
              ready = false;
              throw StateError('iosWdaConnectionLost');
            }
            return {...geometry, 'ready': ready};
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(provider, (_, _) {});
      await pumpEventQueue();
      final notifier = container.read(provider.notifier);
      expect(await notifier.perform('tap', {'x': 1, 'y': 1}), false);
      expect(container.read(provider).ready, false);
      expect(container.read(provider).error, contains('iosWdaConnectionLost'));
      ready = true;
      await notifier.refresh();
      expect(container.read(provider).ready, true);
      expect(container.read(provider).error, isNull);
    },
  );
}
