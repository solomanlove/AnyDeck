import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/window/mirror/model/mirror_error_info.dart';
import 'package:any_deck/app/window/mirror/widget/mirror_status_view.dart';

const List<LocalizationsDelegate<dynamic>> _delegates = [
  AppLocalizationsDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
  group('MirrorErrorInfo 解析测试', () {
    test('正确解析用户截图中的设备离线/未找到错误', () {
      const raw =
          "Failed to push scrcpy-server.jar: adb: error: failed to get feature set: device 'adb-6618d198-XEvEat._adb-tls-connect._tcp' not found";
      final info = MirrorErrorInfo.fromRawError(raw);

      expect(info.type, MirrorErrorType.offline);
      expect(info.isOffline, isTrue);
      expect(info.titleKey, 'deviceDisconnected');
      expect(info.descriptionKey, 'deviceOfflineHint');
      expect(info.rawError, raw);
    });

    test('正确解析 device offline 错误', () {
      const raw = 'adb: error: device offline';
      final info = MirrorErrorInfo.fromRawError(raw);

      expect(info.type, MirrorErrorType.offline);
      expect(info.isOffline, isTrue);
      expect(info.titleKey, 'deviceDisconnected');
      expect(info.descriptionKey, 'deviceOfflineHint');
    });

    test('正确解析设备未授权错误', () {
      const raw =
          'adb: error: device unauthorized. Please check the confirmation dialog on your device.';
      final info = MirrorErrorInfo.fromRawError(raw);

      expect(info.type, MirrorErrorType.unauthorized);
      expect(info.isOffline, isFalse);
      expect(info.titleKey, 'mirrorStartFailed');
      expect(info.descriptionKey, 'deviceUnauthorizedHint');
    });

    test('正确解析连接超时错误', () {
      const raw = 'Connection timed out';
      final info = MirrorErrorInfo.fromRawError(raw);

      expect(info.type, MirrorErrorType.timeout);
      expect(info.isOffline, isFalse);
      expect(info.titleKey, 'mirrorStartFailed');
      expect(info.descriptionKey, 'connectionTimeoutHint');
    });

    test('正确解析未知一般性错误', () {
      const raw = 'Some internal unknown socket crash';
      final info = MirrorErrorInfo.fromRawError(raw);

      expect(info.type, MirrorErrorType.general);
      expect(info.isOffline, isFalse);
      expect(info.titleKey, 'mirrorStartFailed');
      expect(info.fallbackDescription, raw);
    });
  });

  group('MirrorStatusView 组件渲染测试', () {
    testWidgets('设备离线错误时友好展示设备断开文案', (tester) async {
      const raw =
          "Failed to push scrcpy-server.jar: adb: error: failed to get feature set: device 'test' not found";
      var retried = false;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: _delegates,
          home: Scaffold(
            body: MirrorStatusView(
              rawErrorMessage: raw,
              onRetry: () {
                retried = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证标题为友好文案“设备已断开连接”
      expect(find.text('设备已断开连接'), findsOneWidget);
      // 验证副文案为友好提示
      expect(
        find.text('设备已离线或断开连接，请检查 USB 或 Wi-Fi 网络连接后重试'),
        findsOneWidget,
      );
      // 验证重试按钮
      expect(find.text('重试'), findsOneWidget);
      // 验证未展开前不展示原始冷冰冰的堆栈
      expect(find.text(raw), findsNothing);

      // 展开详情
      final viewDetailsButton = find.text('查看错误详情');
      expect(viewDetailsButton, findsOneWidget);
      await tester.tap(viewDetailsButton);
      await tester.pumpAndSettle();

      // 展开后可查看原始报错
      expect(find.text(raw), findsOneWidget);
      expect(find.text('复制错误信息'), findsOneWidget);

      // 点击重试
      await tester.tap(find.text('重试'));
      expect(retried, isTrue);
    });

    testWidgets('未连接/投屏停止状态展示友好文案', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: _delegates,
          home: Scaffold(
            body: MirrorStatusView(
              isStoppedState: true,
              onRetry: _noop,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('未连接或投屏已停止'), findsOneWidget);
      expect(
        find.text('设备已离线或断开连接，请检查 USB 或 Wi-Fi 网络连接后重试'),
        findsOneWidget,
      );
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('英文环境下展示友好的英文断开提示', (tester) async {
      const raw = 'device offline';
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: _delegates,
          home: Scaffold(
            body: MirrorStatusView(
              rawErrorMessage: raw,
              onRetry: _noop,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Device Disconnected'), findsOneWidget);
      expect(
        find.text(
          'Device is offline or disconnected. Please check the USB or Wi-Fi connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

void _noop() {}
