import 'package:any_deck/core/permissions/mac_permission.dart';
import 'package:any_deck/core/permissions/mac_permissions_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/macos_permissions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MacPermissionsService service;
  late List<MethodCall> calls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    service = MacPermissionsService(channel: channel);
    calls = [];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('只读查询保留两项系统状态并忽略旧自动申请字段', () async {
    final reply = <String, Object?>{
      'cameraExtension': 'authorized',
      'loginItems': 'denied',
      'camera': 'authorized',
      'bluetooth': 'restricted',
      'location': 'disabled',
      'notifications': 'denied',
      'localNetwork': 'manual',
      'files': 'manual',
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply;
    });
    final statuses = await service.readAll();
    expect(statuses, {
      MacPermission.cameraExtension: MacPermissionStatus.authorized,
      MacPermission.loginItems: MacPermissionStatus.denied,
    });
    for (final raw in ['manual', 'disabled', 'unsupported']) {
      reply['loginItems'] = raw;
      expect((await service.readAll())[MacPermission.loginItems]!.name, raw);
    }
    reply['cameraExtension'] = 42;
    reply['loginItems'] = 'future_permission_status';
    expect(
      (await service.readAll()).values,
      everyElement(MacPermissionStatus.unknown),
    );
    reply.remove('loginItems');
    expect(
      (await service.readAll())[MacPermission.loginItems],
      MacPermissionStatus.unknown,
    );
    expect(calls.map((call) => call.method), everyElement('readAll'));
  });

  test('读取异常与无效响应继续上抛，不能误当成未授权', () async {
    Object? reply;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (reply is Exception) throw reply;
      return reply;
    });
    for (final invalid in [
      null,
      true,
      ['authorized'],
    ]) {
      reply = invalid;
      await expectLater(
        service.readAll(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'invalid_permission_response',
          ),
        ),
      );
    }
    reply = PlatformException(code: 'system_unavailable');
    await expectLater(
      service.readAll(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'system_unavailable',
        ),
      ),
    );
    expect(calls.map((call) => call.method), everyElement('readAll'));
  });

  test('非 macOS 不访问原生权限接口', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    expect(service.isSupported, isFalse);
    expect(await service.readAll(), {
      MacPermission.cameraExtension: MacPermissionStatus.unsupported,
      MacPermission.loginItems: MacPermissionStatus.unsupported,
    });
    await expectLater(
      service.openSettings(MacPermission.loginItems),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, isEmpty);
  });

  test('设置跳转传递两项权限标识并保留系统打开错误', () async {
    var failOpen = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (failOpen) throw PlatformException(code: 'settings_unavailable');
      return null;
    });
    for (final permission in [
      MacPermission.cameraExtension,
      MacPermission.loginItems,
    ]) {
      await service.openSettings(permission);
      expect(calls.last.method, 'openSettings');
      expect(calls.last.arguments, {'permission': permission.name});
    }
    failOpen = true;
    await expectLater(
      service.openSettings(MacPermission.loginItems),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'settings_unavailable',
        ),
      ),
    );
    expect(calls.last.arguments, {'permission': 'loginItems'});
    expect(calls.map((call) => call.method), everyElement('openSettings'));
  });
}
