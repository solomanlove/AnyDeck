import 'dart:async';
import 'dart:convert';

import 'package:any_deck/core/device_groups/device_groups_controller.dart';
import 'package:any_deck/core/device_groups/device_groups_store.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不启动设备发现，直接验证不同平台及 transport 的身份快照。
RegisteredDevice _device(
  String id, {
  String? serial,
  List<String> connections = const [],
  bool ios = false,
  bool harmony = false,
  bool online = true,
}) => RegisteredDevice(
  id: id,
  status: online ? 'device' : 'offline',
  isOnline: online,
  serial: serial,
  connections: connections,
  isIos: ios,
  isHarmony: harmony,
);

class _ControlledStore extends DeviceGroupsStore {
  DeviceGroupsState saved = DeviceGroupsState();
  bool fail = false;
  bool failLoad = false;
  int writes = 0;
  Completer<void>? barrier;

  @override
  Future<DeviceGroupsState> load() async {
    if (failLoad) throw StateError('read failure');
    return saved;
  }

  @override
  Future<void> save(DeviceGroupsState value) async {
    writes++;
    await barrier?.future;
    if (fail) throw StateError('disk failure');
    saved = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer container({DeviceGroupsStore? store}) {
    final result = ProviderContainer(
      overrides: [
        if (store != null) deviceGroupsStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(result.dispose);
    return result;
  }

  test('AnyDeck 默认平台组自动区分 Android、Harmony、iOS 及离线设备', () {
    final state = DeviceGroupsState();
    expect(state.groups.map((group) => group.name), [
      'Android',
      'Harmony',
      'iOS',
    ]);
    final android = _device('android', online: false);
    final harmony = _device('harmony', harmony: true);
    final ios = _device('airplay-iphone', ios: true);
    expect(state.matches('android', android), isTrue);
    expect(state.matches('android', harmony), isFalse);
    expect(state.matches('android', ios), isFalse);
    expect(state.matches('harmony', harmony), isTrue);
    expect(state.matches('ios', ios), isTrue);
    expect(state.matches(null, ios), isTrue);
    expect(state.matches('deleted', ios), isFalse);
  });

  test('模拟器旧分组会升级为 AVD 身份，复用端口的历史不参与匹配', () {
    final member = DeviceGroupMember(
      platform: DeviceGroupPlatform.android,
      serial: 'emulator-5554',
      aliases: ['emulator-5554'],
    );
    const original = RegisteredDevice(
      id: 'emulator-avd-Old',
      status: 'offline',
      isOnline: false,
      serial: 'emulator-avd-Old',
      emulatorAvdName: 'Old',
      connectionHistory: ['emulator-5554'],
      connections: ['emulator-avd-Old'],
    );
    const current = RegisteredDevice(
      id: 'emulator-5554',
      status: 'device',
      isOnline: true,
      serial: 'emulator-avd-Current',
      emulatorAvdName: 'Current',
      connections: ['emulator-5554'],
      connectionHistory: ['emulator-5554'],
    );
    expect(member.matches(original), isFalse);
    expect(member.matches(current), isFalse);
    final unique = current.copyWith(emulatorIdentityAliases: {'emulator-5554'});
    expect(member.matches(unique), isTrue);
    final upgraded = member.synchronized(unique);
    expect(upgraded.serial, 'emulator-avd-Current');
    expect(upgraded.matches(current.copyWith(id: 'emulator-5556')), isTrue);
  });

  test('AnyDeck 分组名校验首尾空格、重复、空名和长度', () {
    final state = DeviceGroupsState(
      customGroups: [DeviceGroup(id: 'qa', name: 'QA')],
    );
    expect(state.validateName('  '), 'deviceGroupNameEmpty');
    expect(state.validateName('a' * 41), 'deviceGroupNameTooLong');
    expect(state.validateName(' Android '), 'deviceGroupNameDuplicate');
    expect(state.validateName('qa'), 'deviceGroupNameDuplicate');
    expect(state.validateName('qa', excludingId: 'qa'), isNull);
    expect(state.validateName('测试手机'), isNull);
  });

  test('AnyDeck 自定义分组支持重命名、多组归属、移除和删除并持久化', () async {
    final first = container();
    final controller = first.read(deviceGroupsProvider.notifier);
    await first.read(deviceGroupsProvider.future);
    final qa = await controller.createGroup('  测试机  ');
    final personal = await controller.createGroup('常用设备');
    final android = _device('usb', serial: 'physical');
    await controller.setMembership(qa, android, true);
    await controller.setMembership(personal, android, true);
    await controller.renameGroup(qa, '回归测试');

    final restarted = container();
    final restored = await restarted.read(deviceGroupsProvider.future);
    expect(restored.groups.last.name, '常用设备');
    expect(
      restored.groups.where((group) => group.id == qa).single.name,
      '回归测试',
    );
    expect(restored.matches(qa, android), isTrue);
    expect(restored.matches(personal, android), isTrue);

    await controller.setMembership(qa, android, false);
    expect(
      first.read(deviceGroupsProvider).requireValue.matches(qa, android),
      isFalse,
    );
    expect(
      first.read(deviceGroupsProvider).requireValue.matches(personal, android),
      isTrue,
    );
    await controller.deleteGroup(qa);
    expect(first.read(deviceGroupsProvider).requireValue.groups, hasLength(4));
    expect(android.tags, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(DeviceGroupsStore.key)!)['version'], 1);
  });

  test('AnyDeck 已知 serial 跨 USB/TCP 匹配，IP 复用及跨平台不会串组', () async {
    final scope = container();
    final controller = scope.read(deviceGroupsProvider.notifier);
    final id = await controller.createGroup('测试');
    await controller.setMembership(
      id,
      _device(
        'usb',
        serial: 'physical',
        connections: ['usb', '192.168.1.2:5555'],
      ),
      true,
    );
    final state = scope.read(deviceGroupsProvider).requireValue;
    expect(state.matches(id, _device('new-tcp', serial: 'physical')), isTrue);
    expect(
      state.matches(id, _device('192.168.1.2:5555', serial: 'other')),
      isFalse,
    );
    expect(
      state.matches(id, _device('usb', serial: 'physical', harmony: true)),
      isFalse,
    );
    expect(
      state.matches(id, _device('usb', serial: 'physical', ios: true)),
      isFalse,
    );
  });

  test('AnyDeck 无 serial 成员补齐身份后保留后续 USB/TCP 及重启归属', () async {
    final scope = container();
    final controller = scope.read(deviceGroupsProvider.notifier);
    final id = await controller.createGroup('首次连接');
    await controller.setMembership(id, _device('192.168.1.2:5555'), true);
    await controller.synchronizeDevices([
      _device('192.168.1.2:5555', serial: 'physical'),
    ]);
    final state = await container().read(deviceGroupsProvider.future);
    expect(state.matches(id, _device('usb', serial: 'physical')), isTrue);
    expect(
      state.matches(id, _device('192.168.1.2:5555', serial: 'other')),
      isFalse,
    );
  });

  test('AnyDeck 注册表 TCP 占位 serial 补齐后仍保留分组与新 transport', () async {
    final scope = container();
    final controller = scope.read(deviceGroupsProvider.notifier);
    final id = await controller.createGroup('首次 TCP');
    await controller.setMembership(
      id,
      _device('192.168.1.2:5555', serial: '192.168.1.2:5555'),
      true,
    );
    await controller.synchronizeDevices([
      _device('192.168.1.2:5555', serial: 'physical'),
    ]);
    final state = await container().read(deviceGroupsProvider.future);
    expect(
      state.matches(id, _device('192.168.1.3:5555', serial: 'physical')),
      isTrue,
    );
    expect(
      state.matches(
        id,
        _device('192.168.1.2:5555', serial: '192.168.1.2:5555'),
      ),
      isFalse,
    );
    expect(state.matches(id, _device('192.168.1.2:5555')), isFalse);
  });

  test('AnyDeck mDNS 占位可补齐身份，含点硬件序列号保持有效', () async {
    final scope = container();
    final controller = scope.read(deviceGroupsProvider.notifier);
    final id = await controller.createGroup('无线');
    const mdns = 'adb-physical-code._adb-tls-connect._tcp';
    await controller.setMembership(id, _device(mdns, serial: mdns), true);
    await controller.synchronizeDevices([_device(mdns, serial: 'physical')]);
    expect(
      scope
          .read(deviceGroupsProvider)
          .requireValue
          .matches(id, _device('usb', serial: 'physical')),
      isTrue,
    );

    await controller.setMembership(
      id,
      _device('HW.ABC', serial: 'HW.ABC'),
      true,
    );
    expect(
      scope
          .read(deviceGroupsProvider)
          .requireValue
          .matches(id, _device('192.168.1.3:5555', serial: 'HW.ABC')),
      isTrue,
    );
  });

  test('AnyDeck 重复添加成员不会丢失已知 serial 或历史连接别名', () async {
    final scope = container();
    final controller = scope.read(deviceGroupsProvider.notifier);
    final id = await controller.createGroup('测试');
    await controller.setMembership(
      id,
      _device('usb', serial: 'physical'),
      true,
    );
    await controller.setMembership(id, _device('usb'), true);
    final state = scope.read(deviceGroupsProvider).requireValue;
    expect(state.matches(id, _device('new-tcp', serial: 'physical')), isTrue);
    expect(state.customGroups.single.members, hasLength(1));
  });

  test('AnyDeck 默认分组不能编辑、删除或手动添加成员', () async {
    final scope = container();
    final controller = scope.read(deviceGroupsProvider.notifier);
    await expectLater(
      controller.renameGroup('android', '测试'),
      throwsArgumentError,
    );
    await expectLater(controller.deleteGroup('ios'), throwsArgumentError);
    await expectLater(
      controller.setMembership('harmony', _device('usb'), true),
      throwsArgumentError,
    );
    await expectLater(controller.createGroup(' Android '), throwsArgumentError);
    expect(scope.read(deviceGroupsProvider).requireValue.groups, hasLength(3));
    expect(await controller.createGroup('测试'), startsWith('custom-'));
  });

  test('AnyDeck 并发分组操作串行保存，不覆盖其他操作或成员', () async {
    final scope = container();
    final controller = scope.read(deviceGroupsProvider.notifier);
    final ids = await Future.wait([
      controller.createGroup('A'),
      controller.createGroup('B'),
    ]);
    await Future.wait([
      controller.setMembership(ids.first, _device('one'), true),
      controller.setMembership(ids.first, _device('two'), true),
      controller.renameGroup(ids.last, 'C'),
    ]);
    final state = await container().read(deviceGroupsProvider.future);
    expect(state.matches(ids.first, _device('one')), isTrue);
    expect(state.matches(ids.first, _device('two')), isTrue);
    expect(state.groups.last.name, 'C');
    await expectLater(
      Future.wait([controller.createGroup('重复'), controller.createGroup('重复')]),
      throwsArgumentError,
    );
    expect(
      scope.read(deviceGroupsProvider).requireValue.customGroups,
      hasLength(3),
    );
  });

  test('AnyDeck 保存失败保留旧快照，队列后续操作可恢复', () async {
    final store = _ControlledStore();
    final scope = container(store: store);
    final controller = scope.read(deviceGroupsProvider.notifier);
    await scope.read(deviceGroupsProvider.future);
    store.barrier = Completer();
    final pending = controller.createGroup('未保存');
    await Future<void>.delayed(Duration.zero);
    expect(scope.read(deviceGroupsProvider).requireValue.customGroups, isEmpty);
    store.fail = true;
    final failure = expectLater(pending, throwsStateError);
    store.barrier!.complete();
    await failure;
    expect(scope.read(deviceGroupsProvider).requireValue.customGroups, isEmpty);
    store.fail = false;
    store.barrier = null;
    await controller.createGroup('已恢复');
    expect(
      scope.read(deviceGroupsProvider).requireValue.groups.last.name,
      '已恢复',
    );
  });

  test('AnyDeck 读取失败禁止写回覆盖磁盘历史分组', () async {
    final store = _ControlledStore()
      ..saved = DeviceGroupsState(
        customGroups: [DeviceGroup(id: 'kept', name: '历史分组')],
      )
      ..failLoad = true;
    final scope = container(store: store);
    await expectLater(
      scope.read(deviceGroupsProvider.future),
      throwsStateError,
    );
    expect(scope.read(deviceGroupsProvider).hasError, isTrue);
    await expectLater(
      scope.read(deviceGroupsProvider.notifier).createGroup('新建'),
      throwsStateError,
    );
    expect(store.writes, 0);
    expect(store.saved.groups.last.name, '历史分组');
    store.failLoad = false;
    scope.invalidate(deviceGroupsProvider);
    expect(
      (await scope.read(deviceGroupsProvider.future)).groups.last.name,
      '历史分组',
    );
  });

  test('AnyDeck 销毁后停止尚未执行的排队写入', () async {
    final store = _ControlledStore();
    final scope = ProviderContainer(
      overrides: [deviceGroupsStoreProvider.overrideWithValue(store)],
    );
    await scope.read(deviceGroupsProvider.future);
    final controller = scope.read(deviceGroupsProvider.notifier);
    store.barrier = Completer();
    final saving = controller.createGroup('已开始');
    final queued = controller.createGroup('尚未开始');
    final failure = expectLater(queued, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    scope.dispose();
    store.barrier!.complete();
    await saving;
    await failure;
    expect(store.writes, 1);
    expect(store.saved.groups.last.name, '已开始');
  });

  test('AnyDeck 损坏 JSON 显示加载错误且不自动覆盖原值', () async {
    SharedPreferences.setMockInitialValues({DeviceGroupsStore.key: '{broken'});
    final scope = container();
    await expectLater(
      scope.read(deviceGroupsProvider.future),
      throwsFormatException,
    );
    expect(scope.read(deviceGroupsProvider).hasError, isTrue);
    await expectLater(
      scope.read(deviceGroupsProvider.notifier).createGroup('新组'),
      throwsFormatException,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(DeviceGroupsStore.key),
      '{broken',
    );
  });

  test('AnyDeck 坏条目不影响同一快照中的有效分组', () {
    expect(
      () => DeviceGroupsState.fromJson({'version': 2, 'groups': []}),
      throwsFormatException,
    );
    expect(() => DeviceGroupsState.fromJson([]), throwsFormatException);
    final state = DeviceGroupsState.fromJson({
      'version': 1,
      'groups': [
        {'id': 'android', 'name': '篡改默认组', 'members': []},
        {
          'id': 'qa',
          'name': 'QA',
          'members': [
            null,
            {'aliases': []},
          ],
        },
        {'id': 'duplicate', 'name': ' qa ', 'members': []},
        {'id': 1, 'name': '坏条目', 'members': []},
        {'id': 'personal', 'name': '个人', 'members': []},
      ],
    });
    expect(state.groups.map((group) => group.name), [
      'Android',
      'Harmony',
      'iOS',
      'QA',
      '个人',
    ]);
    expect(state.customGroups.first.members, isEmpty);
  });
}
