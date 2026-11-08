import 'dart:async';

import 'package:any_deck/core/dlna/dlna_window_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('窗口通道暂未注册时重试，延迟就绪后成功', () async {
    var attempts = 0;
    expect(
      await waitForDlnaWindowReady(() async {
        attempts++;
        if (attempts < 3) throw StateError('not registered');
        return true;
      }, interval: Duration.zero),
      isTrue,
    );
    expect(attempts, 3);
  });

  test('窗口始终未就绪或通道不返回时均有总时限', () async {
    for (final probe in <Future<bool?> Function()>[
      () async => false,
      () => Completer<bool?>().future,
    ]) {
      expect(
        await waitForDlnaWindowReady(
          probe,
          timeout: const Duration(milliseconds: 30),
          interval: const Duration(milliseconds: 5),
        ),
        isFalse,
      );
    }
  });
}
