import 'package:flutter/material.dart';
import 'package:adb_manage/app/adb_manage_app.dart';
import 'package:adb_manage/core/adb/adb_device.dart';
import 'package:adb_manage/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面外壳基础冒烟测试，测试中会 mock adb 设备轮询。
void main() {
  testWidgets('shows AdbManage shell in Chinese by default', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          devicesProvider.overrideWith((ref) => Stream.value(<AdbDevice>[])),
          emulatorListProvider.overrideWith((ref) => Future.value(<String>[])),
          runningEmulatorsProvider.overrideWith((ref) => Future.value(<String, String>{})),
        ],
        child: const AdbManageApp(),
      ),
    );

    expect(find.text('安卓手机管理'), findsOneWidget);
    expect(find.text('设备管理'), findsWidgets);
    expect(find.text('选择设备'), findsNothing);
  });
}
