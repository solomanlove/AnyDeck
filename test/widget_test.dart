import 'package:adb_manage/app/adb_manage_app.dart';
import 'package:adb_manage/core/adb/adb_device.dart';
import 'package:adb_manage/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows AdbManage shell in Chinese by default', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          devicesProvider.overrideWith((ref) => Stream.value(<AdbDevice>[])),
        ],
        child: const AdbManageApp(),
      ),
    );

    expect(find.text('AdbManage'), findsOneWidget);
    expect(find.text('设备'), findsWidgets);
    expect(find.text('选择设备'), findsOneWidget);
  });
}
