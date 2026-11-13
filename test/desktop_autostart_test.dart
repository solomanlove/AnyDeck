import 'dart:async';

import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/settings/desktop_autostart_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 避免设置加载和窗口注册，使测试只验证自启变更的保存边界。
class _Settings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('any_deck/autostart');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('只读状态区分注册待批准与可运行，未知响应不伪造授权', () async {
    Object? reply = 'requiresApproval';
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return reply;
    });
    expect(
      await DesktopAutoStartService.status(),
      DesktopAutoStartStatus.requiresApproval,
    );
    reply = 'enabled';
    expect(
      await DesktopAutoStartService.status(),
      DesktopAutoStartStatus.enabled,
    );
    for (final unknown in [null, 42, 'future_status']) {
      reply = unknown;
      expect(
        await DesktopAutoStartService.status(),
        DesktopAutoStartStatus.unknown,
      );
    }
    expect(calls, everyElement('status'));
  });

  test('原生注册失败不会改写LaunchAgent回退或吞掉错误', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'blocked'),
    );
    await expectLater(
      DesktopAutoStartService.setEnabled(true),
      throwsA(isA<PlatformException>()),
    );
  });

  test('设置跳转失败保留错误，不解释为批准成功', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      throw PlatformException(code: 'settings_open_failed');
    });
    await expectLater(
      DesktopAutoStartService.openSettings(),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, ['openSettings']);
  });

  test('非macOS不调用登录项接口', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('must not call native'),
    );
    expect(
      await DesktopAutoStartService.status(),
      DesktopAutoStartStatus.unavailable,
    );
    expect(await DesktopAutoStartService.setEnabled(true), isFalse);
  });

  test('注册失败不保存或广播开机自启已开启', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return false;
    });
    final container = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(_Settings.new)],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(appSettingsProvider.notifier).setLaunchAtStartup(true),
      throwsA(isA<PlatformException>()),
    );
    expect(container.read(appSettingsProvider).launchAtStartup, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'settings.launchAtStartup',
      ),
      isNull,
    );
    expect(calls, ['setEnabled']);
  });

  test('接收跨窗口设置只应用偏好，不重复注册系统登录项', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('broadcast must not register'),
    );
    final container = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(_Settings.new)],
    );
    addTearDown(container.dispose);
    await container
        .read(appSettingsProvider.notifier)
        .setLaunchAtStartup(true, broadcast: false, applySystem: false);
    expect(container.read(appSettingsProvider).launchAtStartup, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'settings.launchAtStartup',
      ),
      isTrue,
    );
  });

  test('注册回调在容器销毁后返回不写已释放状态', () async {
    final gate = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (_) => gate.future);
    final container = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(_Settings.new)],
    );
    final pending = container
        .read(appSettingsProvider.notifier)
        .setLaunchAtStartup(true, broadcast: false);
    container.dispose();
    gate.complete(true);
    await expectLater(pending, throwsA(isA<StateError>()));
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'settings.launchAtStartup',
      ),
      isNull,
    );
  });
}
