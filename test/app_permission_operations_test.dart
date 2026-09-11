import 'dart:async';

import 'package:any_deck/core/apps/app_permission_controller.dart';
import 'package:any_deck/core/apps/app_permission_parser.dart';
import 'package:any_deck/core/apps/app_permission_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/permission_adb_fake.dart';

/// 覆盖真实命令边界、多用户隔离、部分失败和操作互斥。
void main() {
  test('当前用户状态、缺失动态权限、未知权限及区块边界', () async {
    final fake = PermissionAdbFake();
    final permissions = await AppPermissionService(
      fake,
    ).getPermissions('device', 'com.example.app');
    expect(permissions, hasLength(5));
    expect(
      permissions.firstWhere((p) => p.name.endsWith('CAMERA')).granted,
      isTrue,
    );
    expect(
      permissions.firstWhere((p) => p.name.endsWith('INTERNET')).isRuntime,
      isFalse,
    );
    expect(
      permissions.firstWhere((p) => p.name.endsWith('NEW_SENSOR')).canChange,
      isTrue,
    );
    expect(
      permissions.firstWhere((p) => p.name.endsWith('UNKNOWN')).isKnownType,
      isFalse,
    );
  });

  test('旧系统安装权限为静态，厂商 protectionLevel 来自设备', () {
    final permissions = parseAppPermissions('''
    requested permissions:
      android.permission.CAMERA
    install permissions:
      android.permission.CAMERA: granted=true
''', 0);
    expect(permissions.single.isRuntime, isFalse);
    expect(
      parsePermissionTypes(
        PermissionAdbFake.metadata,
      )['vendor.permission.NEW_SENSOR'],
      isTrue,
    );
  });

  test('分类查询失败保留 runtime 区块，未识别权限只读', () async {
    final fake = PermissionAdbFake()..failMetadata = true;
    final permissions = await AppPermissionService(
      fake,
    ).getPermissions('device', 'com.example.app');
    expect(
      permissions.firstWhere((p) => p.name.endsWith('CAMERA')).canChange,
      isTrue,
    );
    expect(
      permissions.firstWhere((p) => p.name.endsWith('NEW_SENSOR')).canChange,
      isFalse,
    );
  });

  test('仅撤销已授权动态权限，固定 user 10，部分失败保留原因', () async {
    final fake = PermissionAdbFake()..failMic = true;
    final result = await AppPermissionService(
      fake,
    ).revokeAllRuntimePermissionsDetailed('device', 'com.example.app');
    expect(result.total, 2);
    expect(result.succeeded, 1);
    expect(result.failedPermissions, ['android.permission.RECORD_AUDIO']);
    expect(result.errors.values, contains('policy fixed'));
    final mutations = fake.calls.where((args) => args[1] == 'revoke').toList();
    expect(mutations, hasLength(2));
    expect(
      mutations.every((args) => args[2] == '--user' && args[3] == '10'),
      isTrue,
    );
    expect(fake.calls.where((args) => args.first == 'am'), hasLength(1));
  });

  test('命令成功但实际仍授权，不报告成功', () async {
    final fake = PermissionAdbFake()..ignoreRevoke = true;
    final result = await AppPermissionService(
      fake,
    ).revokeAllRuntimePermissionsDetailed('device', 'com.example.app');
    expect(result.succeeded, 0);
    expect(result.failedPermissions, hasLength(2));
  });

  test('无已授权动态权限不发送撤销命令', () async {
    final fake = PermissionAdbFake()
      ..cameraGranted = false
      ..micGranted = false;
    final result = await AppPermissionService(
      fake,
    ).revokeAllRuntimePermissionsDetailed('device', 'com.example.app');
    expect(result.total, 0);
    expect(fake.calls.where((args) => args[1] == 'revoke'), isEmpty);
  });

  test('当前用户解析失败禁止退回 user 0 进行修改', () async {
    final fake = PermissionAdbFake()..failUser = true;
    await expectLater(
      AppPermissionService(fake).revokePermission(
        'device',
        'com.example.app',
        'android.permission.CAMERA',
      ),
      throwsException,
    );
    expect(fake.calls.where((args) => args[1] == 'revoke'), isEmpty);
  });

  test('确认期间拒绝重复操作，取消后释放锁，筛选不影响批量范围', () async {
    final fake = PermissionAdbFake();
    final container = ProviderContainer(
      overrides: [
        appPermissionServiceProvider.overrideWithValue(
          AppPermissionService(fake),
        ),
      ],
    );
    addTearDown(container.dispose);
    final provider = appPermissionControllerProvider((
      'device',
      'com.example.app',
    ));
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(provider.notifier);
    expect(container.read(provider).loading, isFalse);
    controller.filter(AppPermissionFilter.install);
    controller.search('INTERNET');
    final confirmation = Completer<bool>();
    final pending = controller.revokeAll(() => confirmation.future);
    expect(container.read(provider).busy, isTrue);
    // 面板关闭并重新订阅时，尚未结束的操作仍持有同一个锁。
    subscription.close();
    await container.pump();
    final reopened = container.listen(provider, (_, _) {});
    addTearDown(reopened.close);
    expect(container.read(provider).busy, isTrue);
    expect(await controller.revokeAll(() async => true), isNull);
    await controller.toggle(container.read(provider).permissions.first, false);
    expect(fake.calls.where((args) => args[1] == 'revoke'), isEmpty);
    confirmation.complete(false);
    await pending;
    expect(container.read(provider).busy, isFalse);
    final result = await controller.revokeAll(() async => true);
    expect(result!.succeeded, 2);
    expect(
      container
          .read(provider)
          .permissions
          .where((p) => p.isRuntime && p.granted),
      isEmpty,
    );
  });

  test('断线释放操作锁并暴露错误，刷新可以恢复', () async {
    final fake = PermissionAdbFake();
    final container = ProviderContainer(
      overrides: [
        appPermissionServiceProvider.overrideWithValue(
          AppPermissionService(fake),
        ),
      ],
    );
    addTearDown(container.dispose);
    final provider = appPermissionControllerProvider((
      'device',
      'com.example.app',
    ));
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(provider.notifier);
    fake.failRead = true;
    await controller.revokeAll(() async => true);
    expect(container.read(provider).busy, isFalse);
    expect(container.read(provider).error, contains('offline'));
    fake.failRead = false;
    await controller.refresh();
    expect(container.read(provider).error, isNull);
  });
}
