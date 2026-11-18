import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/modules/registered_device_model.dart';
import 'device_group.dart';
import 'device_groups_store.dart';

export 'device_group.dart';

final deviceGroupsStoreProvider = Provider<DeviceGroupsStore>(
  (ref) => DeviceGroupsStore(),
);

/// 仅主窗口工作区消费；投屏子窗口不读写分组，不引入设备扫描或全局广播。
final deviceGroupsProvider =
    AsyncNotifierProvider<DeviceGroupsController, DeviceGroupsState>(
      DeviceGroupsController.new,
      // 存储/格式错误需用户显式重试，不让自动重试长期掩盖 AsyncError。
      retry: (retryCount, error) => null,
    );

/// 串行保存分组快照，持久化成功后才发布，防止并发写覆盖及失败假成功。
class DeviceGroupsController extends AsyncNotifier<DeviceGroupsState> {
  Future<void> _tail = Future.value();
  int _nextId = 0;

  @override
  Future<DeviceGroupsState> build() =>
      ref.read(deviceGroupsStoreProvider).load();

  Future<T> _serial<T>(Future<T> Function(DeviceGroupsState current) action) {
    final pending = _tail.then((_) async {
      _ensureMounted();
      // 加载失败时沿用失败的 Future，禁止把默认空快照写回覆盖历史分组。
      if (state.hasError) {
        Error.throwWithStackTrace(state.error!, state.stackTrace!);
      }
      final current = state.value ?? await future;
      _ensureMounted();
      return action(current);
    });
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  Future<void> _save(Iterable<DeviceGroup> groups) async {
    _ensureMounted();
    final updated = DeviceGroupsState(customGroups: groups);
    await ref.read(deviceGroupsStoreProvider).save(updated);
    if (ref.mounted) state = AsyncData(updated);
  }

  void _ensureMounted() {
    if (!ref.mounted) throw StateError('Device groups controller disposed');
  }

  String _validatedName(DeviceGroupsState current, String name, {String? id}) {
    final error = current.validateName(name, excludingId: id);
    if (error != null) throw ArgumentError(error);
    return name.trim();
  }

  DeviceGroup _customGroup(DeviceGroupsState current, String id) {
    final group = current.groups.where((group) => group.id == id).firstOrNull;
    if (group == null || group.isBuiltIn) {
      throw ArgumentError('deviceGroupReadOnly');
    }
    return group;
  }

  Future<String> createGroup(String name) => _serial((current) async {
    final cleanName = _validatedName(current, name);
    final id = 'custom-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
    await _save([
      ...current.customGroups,
      DeviceGroup(id: id, name: cleanName),
    ]);
    return id;
  });

  Future<void> renameGroup(String id, String name) => _serial((current) async {
    final group = _customGroup(current, id);
    final cleanName = _validatedName(current, name, id: id);
    await _save([
      for (final entry in current.customGroups)
        entry.id == id ? group.copyWith(name: cleanName) : entry,
    ]);
  });

  Future<void> deleteGroup(String id) => _serial((current) async {
    _customGroup(current, id);
    await _save(current.customGroups.where((group) => group.id != id));
  });

  Future<void> setMembership(
    String groupId,
    RegisteredDevice device,
    bool included,
  ) => _serial((current) async {
    final group = _customGroup(current, groupId);
    final existing = group.members
        .where((member) => member.matches(device))
        .firstOrNull;
    final retained = group.members.where((member) => !member.matches(device));
    final updated = group.copyWith(
      members: [
        ...retained,
        if (included)
          existing?.synchronized(device) ??
              DeviceGroupMember.fromDevice(device),
      ],
    );
    await _save([
      for (final entry in current.customGroups)
        entry.id == groupId ? updated : entry,
    ]);
  });

  /// 注册表身份变化后调用，仅补齐已有归属，不添加新设备或删除暂时离线成员。
  Future<void> synchronizeDevices(List<RegisteredDevice> devices) =>
      _serial((current) async {
        var changed = false;
        final updated = [
          for (final group in current.customGroups)
            group.copyWith(
              members: [
                for (final member in group.members)
                  () {
                    var updated = member;
                    for (final device in devices) {
                      if (!updated.matches(device)) continue;
                      final synchronized = updated.synchronized(device);
                      changed |= !updated.sameIdentity(synchronized);
                      updated = synchronized;
                    }
                    return updated;
                  }(),
              ],
            ),
        ];
        if (changed) await _save(updated);
      });
}
