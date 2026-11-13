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

  test('只读查询保留系统状态，缺失及未来状态不能伪报授权', () async {
    final reply = <String, Object?>{
      'camera': 'authorized',
      'bluetooth': 'restricted',
      'location': 'disabled',
      'notifications': 'denied',
      'localNetwork': 'manual',
      'files': 'future_permission_status',
      'cameraExtension': 42,
      'loginItems': 'future_permission_status',
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply;
    });
    final statuses = await service.readAll();
    expect(statuses[MacPermission.camera], MacPermissionStatus.authorized);
    expect(statuses[MacPermission.bluetooth], MacPermissionStatus.restricted);
    expect(statuses[MacPermission.location], MacPermissionStatus.disabled);
    expect(statuses[MacPermission.notifications], MacPermissionStatus.denied);
    expect(statuses, hasLength(6));
    expect(statuses.keys.map((permission) => permission.name).toSet(), {
      'camera',
      'bluetooth',
      'location',
      'notifications',
      'cameraExtension',
      'loginItems',
    });
    for (final permission in [
      MacPermission.cameraExtension,
      MacPermission.loginItems,
    ]) {
      expect(statuses[permission], MacPermissionStatus.unknown);
    }
    reply.remove('loginItems');
    expect(
      (await service.readAll())[MacPermission.loginItems],
      MacPermissionStatus.unknown,
    );
    reply['loginItems'] = 'manual';
    expect(
      (await service.readAll())[MacPermission.loginItems],
      MacPermissionStatus.manual,
    );
    for (final raw in ['notDetermined', 'unsupported', 'notRequired']) {
      reply['camera'] = raw;
      expect((await service.readAll())[MacPermission.camera]!.name, raw);
    }
    expect(calls.map((call) => call.method), everyElement('readAll'));
  });

  test('读取异常与无效响应继续上抛，不能误当成未申请权限', () async {
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
    expect(
      (await service.readAll()).values,
      everyElement(MacPermissionStatus.unsupported),
    );
    await expectLater(
      service.request(MacPermission.camera),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
      service.openSettings(MacPermission.loginItems),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, isEmpty);
  });

  test('显式申请只允许四种权限，设置跳转保留权限标识与失败', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'openSettings') {
        throw PlatformException(code: 'settings_unavailable');
      }
      return null;
    });
    for (final permission in [
      MacPermission.camera,
      MacPermission.bluetooth,
      MacPermission.location,
      MacPermission.notifications,
    ]) {
      await service.request(permission);
      expect(calls.last.method, 'request');
      expect(calls.last.arguments, {'permission': permission.name});
    }
    for (final permission in [
      MacPermission.cameraExtension,
      MacPermission.loginItems,
    ]) {
      await expectLater(service.request(permission), throwsArgumentError);
    }
    expect(calls, hasLength(4));
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
  });
}
