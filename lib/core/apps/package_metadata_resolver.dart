import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'adb_package.dart';
import 'app_management_service.dart';

/// 全局应用展示元数据解析服务。
///
/// 用于跨设备快照（如使用时长、通知记录、进程列表）中，
/// 当目标设备未安装应用或未拉取图标时，按多级策略尽可能解析并补全
/// 应用的展示名称 (label) 与本地图标文件路径 (iconLocalPath)。
///
/// 解析策略：
/// 1. 若应用已有名称与存在的图标文件，直接返回；
/// 2. 特殊内置应用处理（如 AnyDeck Companion 手机端记录）；
/// 3. 全局内存缓存查找；
/// 4. [AppManagementService] 所有已连接设备的内存缓存遍历；
/// 5. 磁盘图标缓存目录（`~/Library/Caches/AnyDeck/package_icons`）快速检索；
/// 6. 后台异步预热 [SharedPreferences] 中历史设备的全量缓存。
class PackageMetadataResolver {
  PackageMetadataResolver(
    this._appService, {
    this.onCacheUpdated,
  });

  final AppManagementService _appService;

  /// 当后台异步加载出新的包元数据时触发的回调，通知外部刷新 UI
  final void Function()? onCacheUpdated;

  /// 内存中聚合的全局包元数据缓存，key 为 packageName
  final Map<String, AdbPackage> _globalCache = {};

  /// 本地磁盘图标文件匹配缓存，避免高频文件系统扫描
  final Map<String, String?> _diskIconCache = {};

  bool _prefsLoaded = false;
  Future<void>? _loadingPrefsFuture;

  /// 尽力解析单个应用元数据。
  AdbPackage resolve(AdbPackage basePackage, {String? preferredDeviceId}) {
    final packageName = basePackage.name;
    if (packageName.isEmpty) return basePackage;

    // 1. 若已有名称和有效图标，直接记录并返回
    final currentIcon = basePackage.iconLocalPath;
    final currentIconValid =
        currentIcon != null && File(currentIcon).existsSync();
    if (basePackage.label != null &&
        basePackage.label!.trim().isNotEmpty &&
        currentIconValid) {
      _globalCache[packageName] = basePackage;
      return basePackage;
    }

    // 2. 特殊内置应用处理
    if (packageName == 'com.adbmanage.companion') {
      return basePackage.copyWith(
        label: basePackage.label ?? 'AnyDeck 手机记录',
      );
    }

    // 3. 内存聚合缓存匹配
    final cached = _globalCache[packageName];
    String? resolvedLabel = basePackage.label ?? cached?.label;
    String? resolvedIconPath = currentIconValid
        ? currentIcon
        : (cached?.iconLocalPath != null &&
                File(cached!.iconLocalPath!).existsSync()
            ? cached.iconLocalPath
            : null);

    // 4. AppManagementService 内存缓存遍历
    if (resolvedLabel == null || resolvedIconPath == null) {
      final fromMemory = _lookupFromMemory(
        packageName,
        preferredDeviceId: preferredDeviceId,
      );
      if (fromMemory != null) {
        resolvedLabel ??= fromMemory.label;
        if (resolvedIconPath == null &&
            fromMemory.iconLocalPath != null &&
            File(fromMemory.iconLocalPath!).existsSync()) {
          resolvedIconPath = fromMemory.iconLocalPath;
        }
      }
    }

    // 5. 磁盘图标目录快速检索
    resolvedIconPath ??= findIconOnDisk(
      packageName,
      preferredDeviceId: preferredDeviceId,
    );

    // 6. 如果仍然缺少 label 且尚未加载 SharedPreferences 缓存，触发异步预热
    if ((resolvedLabel == null || !_prefsLoaded) && _loadingPrefsFuture == null) {
      warmup();
    }

    final merged = basePackage.copyWith(
      label: resolvedLabel,
      iconLocalPath: resolvedIconPath,
    );

    if (merged.label != null || merged.iconLocalPath != null) {
      _globalCache[packageName] = merged;
    }

    return merged;
  }

  /// 在本地磁盘的 package_icons 目录中查找指定包名的图标文件
  String? findIconOnDisk(String packageName, {String? preferredDeviceId}) {
    if (packageName.isEmpty) return null;
    if (_diskIconCache.containsKey(packageName)) {
      final cachedPath = _diskIconCache[packageName];
      if (cachedPath != null && File(cachedPath).existsSync()) {
        return cachedPath;
      }
    }

    final home = Platform.environment['HOME'];
    final baseDir = home != null && home.isNotEmpty
        ? Directory('$home/Library/Caches/AnyDeck/package_icons')
        : Directory('${Directory.systemTemp.path}/AnyDeck/package_icons');

    if (!baseDir.existsSync()) {
      _diskIconCache[packageName] = null;
      return null;
    }

    try {
      final entities = baseDir.listSync();
      final subDirs = entities.whereType<Directory>().toList();

      // 优先在 preferredDeviceId 目录查找
      if (preferredDeviceId != null && preferredDeviceId.isNotEmpty) {
        final safeId =
            preferredDeviceId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        subDirs.sort((a, b) {
          final aMatch = a.path.contains(safeId);
          final bMatch = b.path.contains(safeId);
          if (aMatch && !bMatch) return -1;
          if (!aMatch && bMatch) return 1;
          return 0;
        });
      }

      for (final dir in subDirs) {
        try {
          final files = dir.listSync().whereType<File>();
          for (final file in files) {
            final fileName = file.uri.pathSegments.last;
            if (fileName.startsWith('$packageName.') ||
                fileName == '$packageName.png') {
              if (file.existsSync() && file.lengthSync() > 0) {
                final path = file.path;
                _diskIconCache[packageName] = path;
                return path;
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    _diskIconCache[packageName] = null;
    return null;
  }

  AdbPackage? _lookupFromMemory(
    String packageName, {
    String? preferredDeviceId,
  }) {
    final memoryCache = _appService.memoryCache;
    if (preferredDeviceId != null) {
      final list = memoryCache[preferredDeviceId];
      if (list != null) {
        for (final p in list) {
          if (p.name == packageName &&
              (p.label != null || p.iconLocalPath != null)) {
            return p;
          }
        }
      }
    }
    for (final entry in memoryCache.entries) {
      if (entry.key == preferredDeviceId) continue;
      for (final p in entry.value) {
        if (p.name == packageName &&
            (p.label != null || p.iconLocalPath != null)) {
          return p;
        }
      }
    }
    return null;
  }

  /// 异步从 SharedPreferences 读取全量历史设备的应用包缓存，构建跨设备全局索引
  Future<void> warmup() {
    if (_prefsLoaded) return Future.value();
    return _loadingPrefsFuture ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final allKeys = prefs.getKeys();
        final packageKeys = allKeys.where(
          (k) =>
              k.startsWith('apps.packages.v4.') ||
              k.startsWith('apps.packages.v3.'),
        );

        var hasNewData = false;
        for (final key in packageKeys) {
          final raw = prefs.getString(key);
          if (raw == null || raw.isEmpty) continue;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is! Map) continue;
            final items = decoded['items'];
            if (items is! List) continue;
            for (final item in items) {
              if (item is! Map) continue;
              final name = item['name'] as String?;
              if (name == null || name.isEmpty) continue;
              final label = item['label'] as String?;
              final iconPath = item['iconLocalPath'] as String?;
              if (label != null || iconPath != null) {
                final existing = _globalCache[name];
                final validIcon =
                    (iconPath != null && File(iconPath).existsSync())
                        ? iconPath
                        : (existing?.iconLocalPath != null &&
                                File(existing!.iconLocalPath!).existsSync()
                            ? existing.iconLocalPath
                            : null);
                final updated = (existing ?? AdbPackage(name: name)).copyWith(
                  label: existing?.label ?? label,
                  iconLocalPath: validIcon,
                );
                _globalCache[name] = updated;
                hasNewData = true;
              }
            }
          } catch (_) {}
        }
        _prefsLoaded = true;
        if (hasNewData) {
          onCacheUpdated?.call();
        }
      } catch (_) {
      } finally {
        _loadingPrefsFuture = null;
      }
    }();
  }
}
