import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'adb_package.dart';
import 'app_management_service.dart';
import 'package_metadata_index.dart';

/// 跨设备展示元数据：UI 只访问有界 LRU，历史快照和图标由磁盘索引按需读取。
class PackageMetadataResolver {
  PackageMetadataResolver(
    this._appService, {
    this.onCacheUpdated,
    PackageMetadataIndex? index,
    this.maxEntries = 2048,
  }) : _index = index == null
           ? PackageMetadataIndex.openDefault
           : (() async => index);

  final AppManagementService _appService;
  final void Function()? onCacheUpdated;
  final int maxEntries;
  final Future<PackageMetadataIndex> Function() _index;
  final _cache = <String, AdbPackage>{};
  final _checkedAt = <String, DateTime>{};
  final _pending = <String, (String, String?)>{};
  final _invalidIcons = <String>{};
  Future<PackageMetadataIndex>? _opening;
  Future<void>? _migration;
  Future<void>? _loading;
  Timer? _timer;
  bool _closed = false;

  int get cachedEntries => _cache.length;
  int get pendingEntries => _pending.length;
  String _key(String name, String? device) => '${device ?? ''}\n$name';

  /// 返回即时展示数据；缺项在后台合批查询，完成后仅广播一次版本更新。
  AdbPackage resolve(AdbPackage basePackage, {String? preferredDeviceId}) {
    final name = basePackage.name;
    if (name.isEmpty) return basePackage;
    if (name == 'com.adbmanage.companion') {
      return basePackage.copyWith(label: basePackage.label ?? 'AnyDeck 手机记录');
    }
    final key = _key(name, preferredDeviceId);
    final cached = _cache.remove(key);
    if (cached != null) _cache[key] = cached;
    if (basePackage.label != null &&
        basePackage.iconLocalPath != null &&
        !_invalidIcons.contains(basePackage.iconLocalPath)) {
      _remember(
        key,
        AdbPackage(
          name: name,
          label: basePackage.label,
          iconLocalPath: basePackage.iconLocalPath,
        ),
      );
      return basePackage;
    }
    final memory = _lookupFromMemory(name, preferredDeviceId);
    final label = basePackage.label ?? cached?.label ?? memory?.label;
    final icon =
        [
              basePackage.iconLocalPath,
              cached?.iconLocalPath,
              memory?.iconLocalPath,
            ]
            .whereType<String>()
            .where((path) => !_invalidIcons.contains(path))
            .firstOrNull;
    if (label == null || icon == null) _request(name, preferredDeviceId);
    _remember(key, AdbPackage(name: name, label: label, iconLocalPath: icon));
    return basePackage.copyWith(
      label: label,
      iconLocalPath: icon,
      clearIconLocalPath: icon == null,
    );
  }

  /// 保留原同步 API，但只读内存；目录扫描与文件存在检查不再发生在 build 中。
  String? findIconOnDisk(String name, {String? preferredDeviceId}) {
    final icon = _cache[_key(name, preferredDeviceId)]?.iconLocalPath;
    if (icon == null || _invalidIcons.contains(icon)) {
      _request(name, preferredDeviceId);
      return null;
    }
    return icon;
  }

  /// Image 解码失败后异步查找替代图标，避免重新把磁盘探测放回 build。
  void reportMissingIcon(
    String name,
    String path, {
    String? preferredDeviceId,
  }) {
    if (_closed) return;
    _invalidIcons.add(path);
    while (_invalidIcons.length > maxEntries) {
      _invalidIcons.remove(_invalidIcons.first);
    }
    final key = _key(name, preferredDeviceId);
    final old = _cache[key];
    if (old != null) _cache[key] = AdbPackage(name: name, label: old.label);
    _checkedAt.remove(key);
    _request(name, preferredDeviceId);
  }

  AdbPackage? _lookupFromMemory(String name, String? preferred) {
    final memory = _appService.memoryCache;
    for (final list in [
      if (memory[preferred] != null) memory[preferred]!,
      ...memory.entries
          .where((entry) => entry.key != preferred)
          .map((entry) => entry.value),
    ]) {
      for (final package in list) {
        if (package.name == name &&
            (package.label != null || package.iconLocalPath != null)) {
          return package;
        }
      }
    }
    return null;
  }

  void _remember(String key, AdbPackage package) {
    _cache.remove(key);
    _cache[key] = package;
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _request(String name, String? device) {
    if (_closed) return;
    final key = _key(name, device);
    final checked = _checkedAt[key];
    if (checked != null &&
        DateTime.now().difference(checked) < const Duration(minutes: 1)) {
      return;
    }
    if (_pending.length >= 128) return;
    _pending[key] = (name, device);
    _timer ??= Timer(const Duration(milliseconds: 20), () {
      _timer = null;
      unawaited(_flush());
    });
  }

  /// 仅准备磁盘索引，不在首屏预热全部历史设备。
  Future<void> warmup() async {
    try {
      await (_opening ??= _index());
    } catch (_) {
      /* 名称/默认图标仍可展示。 */
    }
  }

  Future<void> _migrate(PackageMetadataIndex index) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where(
          (key) =>
              key.startsWith('apps.packages.v4.') ||
              key.startsWith('apps.packages.v3.'),
        )
        .toSet();
    await index.retainSources(keys);
    for (final key in keys) {
      if (_closed) return;
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        await index.importLegacy(key, raw);
      } catch (_) {
        /* 单个旧缓存损坏不阻断其余历史。 */
      }
    }
  }

  Future<void> _flush() {
    if (_closed || _pending.isEmpty) return Future.value();
    return _loading ??= _load().whenComplete(() {
      _loading = null;
      if (!_closed && _pending.isNotEmpty) unawaited(_flush());
    });
  }

  Future<void> _load() async {
    final requests = Map<String, (String, String?)>.from(_pending);
    _pending.clear();
    try {
      final index = await (_opening ??= _index());
      await (_migration ??= _migrate(index));
      if (_closed) return;
      final found = await index.lookup(requests);
      if (_closed) return;
      for (final request in requests.entries) {
        final value = found[request.key] ?? const <String, String>{};
        final old = _cache[request.key];
        _remember(
          request.key,
          AdbPackage(
            name: request.value.$1,
            label: old?.label ?? value['label'],
            iconLocalPath: old?.iconLocalPath ?? value['icon'],
          ),
        );
        _checkedAt.remove(request.key);
        _checkedAt[request.key] = DateTime.now();
      }
      while (_checkedAt.length > maxEntries) {
        _checkedAt.remove(_checkedAt.keys.first);
      }
      onCacheUpdated?.call();
    } catch (_) {
      // 路径或数据库不可用时，保留设备即时元数据；短期负缓存避免 build 重试风暴。
      for (final key in requests.keys) {
        _checkedAt[key] = DateTime.now();
      }
      while (_checkedAt.length > maxEntries) {
        _checkedAt.remove(_checkedAt.keys.first);
      }
    }
  }

  /// 页面所属 Provider 销毁后，迟到的查询不再写 LRU 或触发 UI 更新。
  void dispose() {
    _closed = true;
    _timer?.cancel();
    _pending.clear();
    _cache.clear();
    _checkedAt.clear();
    _invalidIcons.clear();
  }
}
