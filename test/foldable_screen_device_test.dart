import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/foldable/foldable_screen_models.dart';
import 'package:any_deck/core/foldable/foldable_screen_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 显式指定设备才执行有副作用的真机验收；普通测试不会切换已连接的手机。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final deviceId = Platform.environment['ANYDECK_FOLDABLE_DEVICE'];
  test(
    '真机双向切屏、截图尺寸与恢复自动',
    () async {
      final adb = AdbService();
      final service = FoldableScreenService(adb, deviceId!);
      final initial = await service.probe();
      expect(initial, isNotNull, reason: '设备必须提供明确的内外屏运行时映射和控制权限');
      expect(initial!.hasOverride, isFalse, reason: '已有外部状态覆盖时不改变设备');
      final target = initial.currentScreen == FoldableScreen.inner
          ? FoldableScreen.outer
          : FoldableScreen.inner;
      try {
        final switched = await service.select(target);
        expect(switched.currentScreen, target);
        final firstSize = _pngSize(await adb.captureScreenshot(deviceId));
        final returned = await service.select(initial.currentScreen!);
        expect(returned.currentScreen, initial.currentScreen);
        final secondSize = _pngSize(await adb.captureScreenshot(deviceId));
        expect(firstSize, isNot(secondSize));
        final automatic = await service.restoreAutomatic();
        expect(automatic.hasOverride, isFalse);
        // 只记录分辨率，不保存或输出手机截图内容。
        // ignore: avoid_print
        print(
          'Foldable device verified: $firstSize -> $secondSize -> automatic',
        );
      } finally {
        await service.dispose();
      }
      final result = await adb.shellArgs(deviceId, [
        'cmd',
        'device_state',
        'state',
      ]);
      expect(result.isSuccess, isTrue);
      expect(result.stdout, isNot(contains('Override state:')));
    },
    skip: deviceId == null,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

String _pngSize(Uint8List png) {
  expect(png.length, greaterThanOrEqualTo(24));
  final data = ByteData.sublistView(png);
  return '${data.getUint32(16)}x${data.getUint32(20)}';
}
