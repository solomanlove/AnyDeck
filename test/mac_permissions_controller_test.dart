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
  Future<void> Function()? onRequest;
  Future<void> Function()? onOpen;

  @override
  Future<Map<MacPermission, MacPermissionStatus>> readAll() async {
    calls.add('read');
    return onRead == null ? {...statuses} : onRead!();
  }

  @override
  Future<void> request(MacPermission permission) async {
    calls.add('request:${permission.name}');
    await onRequest?.call();
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
      ..statuses = {MacPermission.camera: MacPermissionStatus.authorized};
    final container = _container(service);
    addTearDown(container.dispose);
    final controller = container.read(macPermissionsProvider.notifier);
    expect(service.calls, isEmpty);
    expect(container.read(macPermissionsProvider).loading, isTrue);
    await controller.refresh();
    expect(
      container.read(macPermissionsProvider).statusFor(MacPermission.camera),
      MacPermissionStatus.authorized,
    );
    service.onRead = () async => throw StateError('system unavailable');
    await controller.refresh();
    final failed = container.read(macPermissionsProvider);
    expect(failed.statusFor(MacPermission.camera), MacPermissionStatus.unknown);
    expect(failed.errorKey, 'macPermissionReadFailed');
    expect(failed.loading, isFalse);
    expect(service.calls, ['read', 'read']);
  });

  test('未申请权限只申请一次，完成后按系统结果显示拒绝', () async {
    final gate = Completer<void>();
    final service = _PermissionService()
      ..statuses = {MacPermission.camera: MacPermissionStatus.notDetermined}
      ..onRequest = () => gate.future;
    final container = _container(service);
    addTearDown(container.dispose);
    final controller = container.read(macPermissionsProvider.notifier);
    await controller.refresh();
    final pending = controller.request(MacPermission.camera);
    expect(container.read(macPermissionsProvider).busy, MacPermission.camera);
    await controller.request(MacPermission.camera);
    await controller.openSettings(MacPermission.files);
    expect(service.calls, ['read', 'request:camera']);
    service.statuses = {MacPermission.camera: MacPermissionStatus.denied};
    gate.complete();
    await pending;
    final state = container.read(macPermissionsProvider);
    expect(state.statusFor(MacPermission.camera), MacPermissionStatus.denied);
    expect(state.busy, isNull);
    expect(state.errorKey, isNull);
    expect(service.calls, ['read', 'request:camera', 'read']);
    await controller.request(MacPermission.camera);
    await controller.request(MacPermission.files);
    expect(service.calls, ['read', 'request:camera', 'read']);
  });

  test('申请失败不推断授权成功，保留错误并允许后续重试', () async {
    final service = _PermissionService()
      ..statuses = {MacPermission.location: MacPermissionStatus.notDetermined}
      ..onRequest = () async => throw StateError('request failed');
    final container = _container(service);
    addTearDown(container.dispose);
    final controller = container.read(macPermissionsProvider.notifier);
    await controller.refresh();
    await controller.request(MacPermission.location);
    expect(
      container.read(macPermissionsProvider).errorKey,
      'macPermissionRequestFailed',
    );
    expect(
      container.read(macPermissionsProvider).statusFor(MacPermission.location),
      MacPermissionStatus.notDetermined,
    );
    service.onRequest = () async {
      service.statuses = {
        MacPermission.location: MacPermissionStatus.authorized,
      };
    };
    await controller.request(MacPermission.location);
    expect(
      container.read(macPermissionsProvider).statusFor(MacPermission.location),
      MacPermissionStatus.authorized,
    );
    expect(container.read(macPermissionsProvider).errorKey, isNull);
  });

  test('设置跳转不能当成授权成功，打开失败显示可重试错误', () async {
    final service = _PermissionService()
      ..statuses = {MacPermission.localNetwork: MacPermissionStatus.manual};
    final container = _container(service);
    addTearDown(container.dispose);
    final controller = container.read(macPermissionsProvider.notifier);
    await controller.refresh();
    await controller.openSettings(MacPermission.localNetwork);
    expect(
      container
          .read(macPermissionsProvider)
          .statusFor(MacPermission.localNetwork),
      MacPermissionStatus.manual,
    );
    service.onOpen = () async => throw StateError('settings unavailable');
    await controller.openSettings(MacPermission.localNetwork);
    expect(
      container.read(macPermissionsProvider).errorKey,
      'macPermissionOpenFailed',
    );
    expect(container.read(macPermissionsProvider).busy, isNull);
    expect(service.calls.where((call) => call.startsWith('request')), isEmpty);
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
    second.complete({MacPermission.camera: MacPermissionStatus.denied});
    await latest;
    first.complete({MacPermission.camera: MacPermissionStatus.authorized});
    await earlier;
    expect(
      container.read(macPermissionsProvider).statusFor(MacPermission.camera),
      MacPermissionStatus.denied,
    );
  });

  test('页面销毁后迟到的查询和授权回调不再写入状态', () async {
    final read = Completer<Map<MacPermission, MacPermissionStatus>>();
    final readingService = _PermissionService()..onRead = () => read.future;
    final readingContainer = _container(readingService);
    final reading = readingContainer
        .read(macPermissionsProvider.notifier)
        .refresh();
    readingContainer.dispose();
    read.complete({MacPermission.camera: MacPermissionStatus.authorized});
    await expectLater(reading, completes);

    final request = Completer<void>();
    final service = _PermissionService()
      ..statuses = {MacPermission.camera: MacPermissionStatus.notDetermined}
      ..onRequest = () => request.future;
    final container = _container(service);
    final controller = container.read(macPermissionsProvider.notifier);
    await controller.refresh();
    final requesting = controller.request(MacPermission.camera);
    container.dispose();
    request.complete();
    await expectLater(requesting, completes);
    expect(service.calls, ['read', 'request:camera']);
  });
}
