import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import 'adb_package.dart';

/// 基于 adb 和 PackageManager 实现的应用管理能力。
class AppManagementService {
  AppManagementService(this._adb);

  static const _cacheSchemaVersion = 2;
  static const _packageCachePrefix = 'apps.packages.v2';
  static const _helperAssetPath = 'assets/android/package_icon_helper.dex';
  static const _remoteBaseDir = '/data/local/tmp/adb_manage';
  static const _remoteDexPath = '$_remoteBaseDir/package_icon_helper.dex';
  static const _remotePackageListPath = '$_remoteBaseDir/packages.txt';

  final AdbService _adb;

  /// 优先读取本地缓存；没有缓存或强制刷新时才访问手机。
  Future<List<AdbPackage>> listPackages(
    String deviceId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _loadPackageCache(deviceId);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }
    return refreshPackages(deviceId);
  }

  /// 强制从手机读取已安装应用元数据，并写入本地缓存。
  Future<List<AdbPackage>> refreshPackages(String deviceId) async {
    final packages = await _readPackagesFromDevice(deviceId);
    await _savePackageCache(deviceId, packages);
    return packages;
  }

  Future<List<AdbPackage>> _readPackagesFromDevice(String deviceId) async {
    final results = await Future.wait([
      _adb.shellArgs(deviceId, ['pm', 'list', 'packages', '-f', '-U']),
      _adb.shellArgs(deviceId, ['pm', 'list', 'packages', '-s']),
      _adb.shellArgs(deviceId, ['pm', 'list', 'packages', '-d']),
      _adb.shellArgs(deviceId, ['dumpsys', 'package', 'packages']),
      _adb.shell(deviceId, _packageSizeCommand),
      _adb.shell(deviceId, _flutterPackageCommand),
    ]);

    final packageListResult = results[0];
    if (!packageListResult.isSuccess) {
      throw Exception(packageListResult.message);
    }

    final listedPackages = _parsePackageList(packageListResult.stdout);
    final systemPackages = _parsePackageNames(results[1].stdout);
    final disabledPackages = _parsePackageNames(results[2].stdout);
    final dumpMetadata = _parsePackageDump(results[3].stdout);
    final sizes = _parsePackageSizes(results[4].stdout);
    final flutterPackages = _parseLineSet(results[5].stdout);

    final packages = listedPackages
        .map((listed) {
          final metadata = dumpMetadata[listed.name];
          return AdbPackage(
            name: listed.name,
            label: metadata?.label,
            apkPath: listed.apkPath,
            versionName: metadata?.versionName,
            versionCode: metadata?.versionCode,
            minSdk: metadata?.minSdk,
            targetSdk: metadata?.targetSdk,
            maxSdk: metadata?.maxSdk,
            storageBytes: sizes[listed.name],
            enabled: !disabledPackages.contains(listed.name),
            system:
                systemPackages.contains(listed.name) ||
                metadata?.system == true ||
                _looksLikeSystemPath(listed.apkPath),
            flutter: flutterPackages.contains(listed.name),
          );
        })
        .toList(growable: false);

    final enrichedPackages = await _enrichPackagesWithIcons(deviceId, packages);

    return enrichedPackages..sort(
      (left, right) => left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      ),
    );
  }

  Future<List<AdbPackage>?> _loadPackageCache(String deviceId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_packageCacheKey(deviceId));
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != _cacheSchemaVersion) {
        return null;
      }
      final items = decoded['items'];
      if (items is! List) {
        return null;
      }
      final packages = items
          .whereType<Map>()
          .map((item) => AdbPackage.fromJson(Map<String, Object?>.from(item)))
          .where((package) => package.name.isNotEmpty)
          .toList(growable: false);
      return packages..sort(_comparePackages);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _savePackageCache(
    String deviceId,
    List<AdbPackage> packages,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'schemaVersion': _cacheSchemaVersion,
      'savedAt': DateTime.now().toIso8601String(),
      'items': packages.map((package) => package.toJson()).toList(),
    });
    await preferences.setString(_packageCacheKey(deviceId), payload);
  }

  String _packageCacheKey(String deviceId) {
    return '$_packageCachePrefix.$deviceId';
  }

  int _comparePackages(AdbPackage left, AdbPackage right) {
    return left.displayName.toLowerCase().compareTo(
      right.displayName.toLowerCase(),
    );
  }

  Future<List<AdbPackage>> _enrichPackagesWithIcons(
    String deviceId,
    List<AdbPackage> packages,
  ) async {
    try {
      await _ensureIconHelperPushed(deviceId);
      final packageListFile = await _writePackageListFile(deviceId, packages);
      final pushListResult = await _adb.run([
        '-s',
        deviceId,
        'push',
        packageListFile.path,
        _remotePackageListPath,
      ]);
      if (!pushListResult.isSuccess) {
        return packages;
      }

      final userId = await _currentUserId(deviceId);
      final result = await _adb.shell(
        deviceId,
        'CLASSPATH=$_remoteDexPath app_process /system/bin '
        'com.adbmanage.helper.PackageIconHelper '
        '$_remotePackageListPath $userId',
      );
      if (!result.isSuccess) {
        return packages;
      }

      final iconInfos = _parseIconHelperOutput(result.stdout);
      if (iconInfos.isEmpty) {
        return packages;
      }

      final enriched = <AdbPackage>[];
      for (final package in packages) {
        final iconInfo = iconInfos[package.name];
        if (iconInfo == null) {
          enriched.add(package);
          continue;
        }
        final iconLocalPath = await _pullIconIfNeeded(deviceId, iconInfo);
        enriched.add(
          package.copyWith(
            label: iconInfo.label.isEmpty ? null : iconInfo.label,
            iconLocalPath: iconLocalPath,
            iconRemotePath: iconInfo.remotePath.isEmpty
                ? null
                : iconInfo.remotePath,
          ),
        );
      }
      return enriched;
    } catch (_) {
      return packages;
    }
  }

  Future<void> _ensureIconHelperPushed(String deviceId) async {
    final helperFile = await _writeHelperAssetToTemp();
    await _adb.shell(deviceId, 'mkdir -p $_remoteBaseDir/icons');
    await _adb.run(['-s', deviceId, 'push', helperFile.path, _remoteDexPath]);
  }

  Future<File> _writeHelperAssetToTemp() async {
    final bytes = await rootBundle.load(_helperAssetPath);
    final dir = Directory('${Directory.systemTemp.path}/adb_manage_helper');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/package_icon_helper.dex');
    await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    return file;
  }

  Future<File> _writePackageListFile(
    String deviceId,
    List<AdbPackage> packages,
  ) async {
    final dir = Directory('${Directory.systemTemp.path}/adb_manage_packages');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/${_safeFileSegment(deviceId)}.txt');
    await file.writeAsString(
      packages.map((package) => package.name).join('\n'),
      flush: true,
    );
    return file;
  }

  Future<int> _currentUserId(String deviceId) async {
    final result = await _adb.shellArgs(deviceId, ['am', 'get-current-user']);
    if (!result.isSuccess) {
      return 0;
    }
    return int.tryParse(result.stdout.trim()) ?? 0;
  }

  Map<String, _IconHelperInfo> _parseIconHelperOutput(String output) {
    final infos = <String, _IconHelperInfo>{};
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final parts = trimmed.split('\t');
      if (parts.length < 3) {
        continue;
      }
      infos[parts[0]] = _IconHelperInfo(
        packageName: parts[0],
        label: _decodeBase64(parts[1]),
        remotePath: parts[2],
      );
    }
    return infos;
  }

  String _decodeBase64(String value) {
    if (value.isEmpty) {
      return '';
    }
    try {
      return utf8.decode(base64Decode(value));
    } on FormatException {
      return '';
    }
  }

  Future<String?> _pullIconIfNeeded(
    String deviceId,
    _IconHelperInfo iconInfo,
  ) async {
    final remotePath = iconInfo.remotePath;
    if (remotePath.isEmpty) {
      return null;
    }

    final fileName = remotePath.split('/').last;
    if (fileName.isEmpty) {
      return null;
    }
    final dir = _localIconCacheDir(deviceId);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final localFile = File('${dir.path}/${_safeFileSegment(fileName)}');
    if (localFile.existsSync() && localFile.lengthSync() > 0) {
      return localFile.path;
    }

    final result = await _adb.run([
      '-s',
      deviceId,
      'pull',
      remotePath,
      localFile.path,
    ]);
    return result.isSuccess && localFile.existsSync() ? localFile.path : null;
  }

  Directory _localIconCacheDir(String deviceId) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory(
        '$home/Library/Caches/AdbManage/package_icons/${_safeFileSegment(deviceId)}',
      );
    }
    return Directory(
      '${Directory.systemTemp.path}/AdbManage/package_icons/${_safeFileSegment(deviceId)}',
    );
  }

  String _safeFileSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  static const _packageSizeCommand = '''
for line in \$(pm list packages -f | sed 's/^package://'); do
  path=\${line%=*}
  pkg=\${line##*=}
  size=\$(du -sk "\$path" 2>/dev/null | awk '{print \$1}')
  echo "\$pkg\t\${size:-0}"
done
''';

  static const _flutterPackageCommand = '''
for file in \$(find /data/app /system/app /system/priv-app /product/app /product/priv-app /vendor/app /vendor/priv-app -name libflutter.so 2>/dev/null); do
  best=""
  bestLen=0
  for line in \$(pm list packages -f | sed 's/^package://'); do
    path=\${line%=*}
    pkg=\${line##*=}
    dir=\$(dirname "\$path")
    case "\$file" in
      "\$dir"/*)
        len=\${#dir}
        if [ "\$len" -gt "\$bestLen" ]; then
          best="\$pkg"
          bestLen=\$len
        fi
        ;;
    esac
  done
  [ -n "\$best" ] && echo "\$best"
done | sort -u
''';

  /// 从宿主机安装或覆盖安装 APK。
  Future<AdbResult> installApk(String deviceId, String apkPath) {
    return _adb.run(['-s', deviceId, 'install', '-r', apkPath]);
  }

  /// 从设备卸载指定应用包。
  Future<AdbResult> uninstall(String deviceId, String packageName) {
    return _adb.run(['-s', deviceId, 'uninstall', packageName]);
  }

  /// 通过 monkey 启动应用默认入口 Activity。
  Future<AdbResult> launch(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['monkey', '-p', packageName, '1']);
  }

  /// 强停目标应用进程，但不清除应用数据。
  Future<AdbResult> forceStop(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['am', 'force-stop', packageName]);
  }

  /// 通过 Android PackageManager 清除应用数据。
  Future<AdbResult> clearData(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['pm', 'clear', packageName]);
  }

  /// 查询应用在设备上的 APK 安装路径。
  Future<AdbResult> packagePath(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['pm', 'path', packageName]);
  }

  List<_ListedPackage> _parsePackageList(String output) {
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('package:'))
        .map(_parsePackageListLine)
        .toList(growable: false);
  }

  _ListedPackage _parsePackageListLine(String line) {
    final value = line.substring('package:'.length);
    final parts = value.split(RegExp(r'\s+'));
    final pathAndName = parts.first;
    final separator = pathAndName.lastIndexOf('=');
    if (separator <= 0 || separator == pathAndName.length - 1) {
      return _ListedPackage(name: pathAndName);
    }
    return _ListedPackage(
      apkPath: pathAndName.substring(0, separator),
      name: pathAndName.substring(separator + 1),
    );
  }

  Set<String> _parsePackageNames(String output) {
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('package:'))
        .map((line) => line.substring('package:'.length).split(' ').first)
        .toSet();
  }

  Map<String, _PackageDumpMetadata> _parsePackageDump(String output) {
    final packages = <String, _PackageDumpMetadata>{};
    final buffer = StringBuffer();
    String? currentPackage;

    void flush() {
      final packageName = currentPackage;
      if (packageName == null) {
        return;
      }
      packages[packageName] = _parseDumpBlock(buffer.toString());
      buffer.clear();
    }

    for (final line in output.split('\n')) {
      final match = RegExp(r'^\s*Package \[([^\]]+)\]').firstMatch(line);
      if (match != null) {
        flush();
        currentPackage = match.group(1);
      }
      if (currentPackage != null) {
        buffer.writeln(line);
      }
    }
    flush();
    return packages;
  }

  _PackageDumpMetadata _parseDumpBlock(String block) {
    return _PackageDumpMetadata(
      label: _firstMatch(block, RegExp(r'label=([^\s]+)')),
      versionName: _firstMatch(block, RegExp(r'versionName=([^\s]+)')),
      versionCode: _firstMatch(block, RegExp(r'versionCode=([^\s]+)')),
      minSdk: _parseInt(_firstMatch(block, RegExp(r'minSdk=(\d+)'))),
      targetSdk: _parseInt(_firstMatch(block, RegExp(r'targetSdk=(\d+)'))),
      maxSdk: _parseInt(_firstMatch(block, RegExp(r'maxSdk=(\d+)'))),
      system:
          block.contains('pkgFlags=[') &&
          (block.contains(' SYSTEM ') ||
              block.contains('[ SYSTEM') ||
              block.contains(' UPDATED_SYSTEM_APP ')),
    );
  }

  Map<String, int> _parsePackageSizes(String output) {
    final sizes = <String, int>{};
    for (final line in output.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }
      final kb = int.tryParse(parts[1]);
      if (kb != null) {
        sizes[parts.first] = kb * 1024;
      }
    }
    return sizes;
  }

  Set<String> _parseLineSet(String output) {
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet();
  }

  String? _firstMatch(String input, RegExp pattern) {
    return pattern.firstMatch(input)?.group(1);
  }

  int? _parseInt(String? value) {
    return value == null ? null : int.tryParse(value);
  }

  bool _looksLikeSystemPath(String? path) {
    if (path == null) {
      return false;
    }
    return path.startsWith('/system/') ||
        path.startsWith('/product/') ||
        path.startsWith('/vendor/') ||
        path.startsWith('/apex/');
  }
}

class _ListedPackage {
  const _ListedPackage({required this.name, this.apkPath});

  final String name;
  final String? apkPath;
}

class _PackageDumpMetadata {
  const _PackageDumpMetadata({
    this.label,
    this.versionName,
    this.versionCode,
    this.minSdk,
    this.targetSdk,
    this.maxSdk,
    this.system = false,
  });

  final String? label;
  final String? versionName;
  final String? versionCode;
  final int? minSdk;
  final int? targetSdk;
  final int? maxSdk;
  final bool system;
}

class _IconHelperInfo {
  const _IconHelperInfo({
    required this.packageName,
    required this.label,
    required this.remotePath,
  });

  final String packageName;
  final String label;
  final String remotePath;
}
