import 'dart:async';

import 'package:any_deck/core/permissions/mac_permission.dart';
import 'package:any_deck/core/permissions/mac_permissions_controller.dart';
import 'package:any_deck/core/permissions/mac_permissions_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用可控的系统返回与等待门验证异步行为，不触发真实 macOS 授权。
class _PermissionService extends MacPermissionsService {
  final calls = <String>[];
  Map<MacPermission, MacPermissionStatus> statuses = {};
  Future<Map<MacPermission, MacPermissionStatus>> Function()? onRead;
  Future<void> Function()? onOpen;

  @override
  Future<Map<MacPermission, MacPermissionStatus>> readAll() async {
    calls.add('read');
    return onRead == null ? {...statuses} : onRead!();
  }

  @override
  Future<void> openSettings(MacPermission permission) async {
    calls.add('open:${permission.name}');
    await onOpen?.call();
  }
}

ProviderContainer _container(_PermissionService service) {
  final container = ProviderContainer(
    overrides: [macPermissionsServiceProvider.overrideWithValue(service)],
  );
  container.listen(macPermissionsProvider, (_, _) {});
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('进入页面仅查询权限，读取失败清除过期授权结论', () async {
    final service = _PermissionService()
      ..statuses = {
        MacPermission.cameraExtension: MacPermissionStatus.authorized,
      };
    final container = _container(service);
    addTearDown(container.dispose);
    final controller = container.read(macPermissionsProvider.notifier);
    expect(service.calls, isEmpty);
    expect(container.read(macPermissionsProvider).loading, isTrue);
    await controller.refresh();
    expect(
      container
          .read(macPermissionsProvider)
          .statusFor(MacPermission.cameraExtension),
      MacPermissionStatus.authorized,
    );
    service.onRead = () async => throw StateError('system unavailable');
    await controller.refresh();
    final failed = container.read(macPermissionsProvider);
    expect(
      failed.statusFor(MacPermission.cameraExtension),
      MacPermissionStatus.unknown,
    );
    expect(failed.errorKey, 'macPermissionReadFailed');
    expect(failed.loading, isFalse);
    expect(service.calls, ['read', 'read']);
  });

  test('读取完成前及设置打开期间不能重复操作，跳转不代表授权成功', () async {
    final gate = Completer<void>();
    final service = _PermissionService()
      ..statuses = {MacPermission.loginItems: MacPermissionStatus.denied}
      ..onOpen = () => gate.future;
    final container = _container(service);
    addTearDown(container.dispose);
    final controller = container.read(macPermissionsProvider.notifier);
    await controller.openSettings(MacPermission.loginItems);
    expect(service.calls, isEmpty);
    await controller.refresh();
    final pending = controller.openSettings(MacPermission.loginItems);
    expect(
      container.read(macPermissionsProvider).busy,
      MacPermission.loginItems,
    );
    await controller.openSettings(MacPermission.loginItems);
    await controller.openSettings(MacPermission.cameraExtension);
    expect(service.calls, ['read', 'open:loginItems']);
    gate.complete();
    await pending;
    final state = container.read(macPermissionsProvider);
    expect(
      state.statusFor(MacPermission.loginItems),
      MacPermissionStatus.denied,
    );
    expect(state.busy, isNull);
    expect(state.errorKey, isNull);
    expect(service.calls, ['read', 'open:loginItems', 'read']);
  });

  test('打开失败保留错误并允许重试，状态仅采信重新读取的系统结果', () async {
    final service = _PermissionService()
      ..statuses = {MacPermission.loginItems: MacPermissionStatus.manual}
      ..onOpen = () async => throw StateError('settings unavailable');
    final container = _container(service);
    addTearDown(container.dispose);
    final controller = container.read(macPermissionsProvider.notifier);
    await controller.refresh();
    await controller.openSettings(MacPermission.loginItems);
    expect(
      container.read(macPermissionsProvider).errorKey,
      'macPermissionOpenFailed',
    );
    expect(
      container
          .read(macPermissionsProvider)
          .statusFor(MacPermission.loginItems),
      MacPermissionStatus.manual,
    );
    expect(container.read(macPermissionsProvider).busy, isNull);
    service.onOpen = () async {
      service.statuses = {
        MacPermission.loginItems: MacPermissionStatus.authorized,
      };
    };
    await controller.openSettings(MacPermission.loginItems);
    expect(
      container
          .read(macPermissionsProvider)
          .statusFor(MacPermission.loginItems),
      MacPermissionStatus.authorized,
    );
    expect(container.read(macPermissionsProvider).errorKey, isNull);
    expect(service.calls, [
      'read',
      'open:loginItems',
      'read',
      'open:loginItems',
      'read',
    ]);
  });

  test('较早发起的授权快照不能覆盖最新刷新结果', () async {
    final first = Completer<Map<MacPermission, MacPermissionStatus>>();
    final second = Completer<Map<MacPermission, MacPermissionStatus>>();
    final service = _PermissionService();
    var reads = 0;
    service.onRead = () => ++reads == 1 ? first.future : second.future;
    final container = _container(service);
    addTearDown(container.dispose);
    final controller = container.read(macPermissionsProvider.notifier);
    final earlier = controller.refresh();
    final latest = controller.refresh();
    second.complete({MacPermission.loginItems: MacPermissionStatus.denied});
    await latest;
    first.complete({MacPermission.loginItems: MacPermissionStatus.authorized});
    await earlier;
    expect(
      container
          .read(macPermissionsProvider)
          .statusFor(MacPermission.loginItems),
      MacPermissionStatus.denied,
    );
  });

  test('页面销毁后迟到的查询和设置回调不再写入状态', () async {
    final read = Completer<Map<MacPermission, MacPermissionStatus>>();
    final readingService = _PermissionService()..onRead = () => read.future;
    final readingContainer = _container(readingService);
    final reading = readingContainer
        .read(macPermissionsProvider.notifier)
        .refresh();
    readingContainer.dispose();
    read.complete({
      MacPermission.cameraExtension: MacPermissionStatus.authorized,
    });
    await expectLater(reading, completes);

    final open = Completer<void>();
    final service = _PermissionService()
      ..statuses = {MacPermission.loginItems: MacPermissionStatus.denied}
      ..onOpen = () => open.future;
    final container = _container(service);
    final controller = container.read(macPermissionsProvider.notifier);
    await controller.refresh();
    final opening = controller.openSettings(MacPermission.loginItems);
    container.dispose();
    open.complete();
    await expectLater(opening, completes);
    expect(service.calls, ['read', 'open:loginItems']);
  });
}
