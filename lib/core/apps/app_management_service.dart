import 'dart:async';
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

  static const _cacheSchemaVersion = 3;
  static const _packageCachePrefix = 'apps.packages.v3';
  static const _helperAssetPath = 'assets/android/package_icon_helper.dex';
  static const _remoteBaseDir = '/data/local/tmp/any_deck';
  static const _remoteDexPath = '$_remoteBaseDir/package_icon_helper.dex';
  static const _remotePackageListPath = '$_remoteBaseDir/packages.txt';
  static const _quickTimeout = Duration(seconds: 8);
  static const _metadataTimeout = Duration(seconds: 10);
  static const _fileTransferTimeout = Duration(minutes: 5);

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
    return _readFastPackagesFromDevice(deviceId);
  }

  /// 强制从手机读取已安装应用元数据，并写入本地缓存。
  Future<List<AdbPackage>> refreshPackages(
    String deviceId, {
    bool refreshIconsInBackground = true,
  }) async {
    final cachedPackages = await _loadPackageCache(deviceId);
    final packages = _restoreCachedPresentationData(
      await _readPackagesFromDevice(deviceId),
      cachedPackages,
    );
    await _savePackageCache(deviceId, packages);
    if (refreshIconsInBackground) {
      unawaited(_refreshPackageIconCache(deviceId, packages));
    }
    return packages;
  }

  Future<AdbResult> _getDumpsysMetadata(String deviceId) async {
    const dumpsysCmd =
        'dumpsys package packages | grep -E "Package \\[|versionName=|versionCode=|minSdk=|targetSdk=|maxSdk=|pkgFlags=\\["';
    try {
      final filteredResult = await _adb.shell(
        deviceId,
        dumpsysCmd,
        timeout: _metadataTimeout,
      );
      if (filteredResult.isSuccess && filteredResult.stdout.trim().isNotEmpty) {
        return filteredResult;
      }
    } catch (_) {}

    return _adb.shellArgs(deviceId, [
      'dumpsys',
      'package',
      'packages',
    ], timeout: _metadataTimeout);
  }

  Future<List<AdbPackage>> _readPackagesFromDevice(String deviceId) async {
    final results = await Future.wait<AdbResult>([
      _adb.shellArgs(deviceId, [
        'pm',
        'list',
        'packages',
        '-f',
        '-U',
        '--user',
        '0',
      ], timeout: _quickTimeout),
      _adb.shellArgs(deviceId, [
        'pm',
        'list',
        'packages',
        '-s',
        '--user',
        '0',
      ], timeout: _quickTimeout),
      _adb.shellArgs(deviceId, [
        'pm',
        'list',
        'packages',
        '-f',
        '-U',
        '-d',
        '--user',
        '0',
      ], timeout: _quickTimeout),
      _getDumpsysMetadata(deviceId),
      _adb.shell(deviceId, _packageSizeCommand, timeout: _metadataTimeout),
      _adb.shell(deviceId, _flutterPackageCommand, timeout: _metadataTimeout),
    ]);

    final packageListResult = results[0];
    if (!packageListResult.isSuccess) {
      throw Exception(packageListResult.message);
    }

    final listedPackages = _mergeListedPackages(
      _parsePackageList(packageListResult.stdout),
      results[2].isSuccess
          ? _parsePackageList(results[2].stdout)
          : const <_ListedPackage>[],
    );
    final systemPackages = results[1].isSuccess
        ? _parsePackageNames(results[1].stdout)
        : <String>{};
    final disabledPackages = results[2].isSuccess
        ? _parsePackageList(
            results[2].stdout,
          ).map((package) => package.name).toSet()
        : <String>{};
    final dumpMetadata = results[3].isSuccess
        ? _parsePackageDump(results[3].stdout)
        : <String, _PackageDumpMetadata>{};
    final sizes = results[4].isSuccess
        ? _parsePackageSizes(results[4].stdout)
        : <String, int>{};
    final flutterPackages = results[5].isSuccess
        ? _parseLineSet(results[5].stdout)
        : <String>{};

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
            debuggable: metadata?.debuggable == true,
          );
        })
        .toList(growable: false);

    final sortedPackages = packages
      ..sort(
        (left, right) => left.displayName.toLowerCase().compareTo(
          right.displayName.toLowerCase(),
        ),
      );
    return sortedPackages;
  }

  Future<List<AdbPackage>> _readFastPackagesFromDevice(String deviceId) async {
    final results = await Future.wait<AdbResult>([
      _adb.shellArgs(deviceId, [
        'pm',
        'list',
        'packages',
        '-f',
        '-U',
        '--user',
        '0',
      ], timeout: _quickTimeout),
      _adb.shellArgs(deviceId, [
        'pm',
        'list',
        'packages',
        '-s',
        '--user',
        '0',
      ], timeout: _quickTimeout),
      _adb.shellArgs(deviceId, [
        'pm',
        'list',
        'packages',
        '-f',
        '-U',
        '-d',
        '--user',
        '0',
      ], timeout: _quickTimeout),
    ]);

    final packageListResult = results[0];
    if (!packageListResult.isSuccess) {
      throw Exception(packageListResult.message);
    }

    final listedPackages = _mergeListedPackages(
      _parsePackageList(packageListResult.stdout),
      results[2].isSuccess
          ? _parsePackageList(results[2].stdout)
          : const <_ListedPackage>[],
    );
    final systemPackages = results[1].isSuccess
        ? _parsePackageNames(results[1].stdout)
        : <String>{};
    final disabledPackages = results[2].isSuccess
        ? _parsePackageList(
            results[2].stdout,
          ).map((package) => package.name).toSet()
        : <String>{};

    final packages = listedPackages
        .map(
          (listed) => AdbPackage(
            name: listed.name,
            apkPath: listed.apkPath,
            enabled: !disabledPackages.contains(listed.name),
            system:
                systemPackages.contains(listed.name) ||
                _looksLikeSystemPath(listed.apkPath),
          ),
        )
        .toList(growable: false);

    return packages..sort(_comparePackages);
  }

  List<AdbPackage> _restoreCachedPresentationData(
    List<AdbPackage> packages,
    List<AdbPackage>? cachedPackages,
  ) {
    if (cachedPackages == null || cachedPackages.isEmpty) {
      return packages;
    }
    final cachedByName = {
      for (final package in cachedPackages) package.name: package,
    };
    return packages
        .map((package) {
          final cached = cachedByName[package.name];
          if (cached == null) {
            return package;
          }
          return package.copyWith(
            label: cached.label,
            iconLocalPath: cached.iconLocalPath,
            iconRemotePath: cached.iconRemotePath,
            signatureMd5: cached.signatureMd5,
            firstInstallTime: cached.firstInstallTime,
            lastUpdateTime: cached.lastUpdateTime,
          );
        })
        .toList(growable: false)
      ..sort(_comparePackages);
  }

  Future<void> _refreshPackageIconCache(
    String deviceId,
    List<AdbPackage> packages,
  ) async {
    try {
      await enrichPackagesWithIconsProgressive(deviceId, packages).drain();
    } catch (_) {
      // 后台图标缓存失败不影响首屏应用列表展示。
    }
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

  Future<List<AdbPackage>?> loadPackageCache(String deviceId) {
    return _loadPackageCache(deviceId);
  }

  Future<void> savePackageCache(String deviceId, List<AdbPackage> packages) {
    return _savePackageCache(deviceId, packages);
  }

  Future<void> clearPackageCache(String deviceId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_packageCacheKey(deviceId));
  }

  /// 清除某个设备的所有相关本地缓存，包括包列表缓存和本机的本地图标缓存目录，以及临时 chunk 文件。
  Future<void> clearDeviceCache(String deviceId) async {
    // 1. 清除 package 信息的 SharedPreferences 缓存
    await clearPackageCache(deviceId);

    // 2. 清除本机的本地图标缓存文件夹
    try {
      final iconDir = _localIconCacheDir(deviceId);
      if (iconDir.existsSync()) {
        await iconDir.delete(recursive: true);
      }
    } catch (_) {
      // 允许清理本地图标目录失败时不抛出异常
    }

    // 3. 清除临时 chunk 文件
    try {
      final chunkDir = Directory('${Directory.systemTemp.path}/any_deck_packages');
      if (chunkDir.existsSync()) {
        final safeId = _safeFileSegment(deviceId);
        final list = chunkDir.listSync();
        for (final file in list) {
          if (file is File && file.path.contains('${safeId}_chunk_')) {
            await file.delete();
          }
        }
      }
    } catch (_) {
      // 允许清理临时文件失败时不抛出异常
    }
  }

  int _comparePackages(AdbPackage left, AdbPackage right) {
    return left.displayName.toLowerCase().compareTo(
      right.displayName.toLowerCase(),
    );
  }

  Stream<List<AdbPackage>> enrichPackagesWithIconsProgressive(
    String deviceId,
    List<AdbPackage> packages,
  ) async* {
    try {
      await _ensureIconHelperPushed(deviceId);
      final userId = await _currentUserId(deviceId);

      // 分批提取图标（每批 50 个应用）
      const chunkSize = 50;
      final currentPackages = List<AdbPackage>.from(packages);

      for (var i = 0; i < currentPackages.length; i += chunkSize) {
        final end = (i + chunkSize < currentPackages.length)
            ? i + chunkSize
            : currentPackages.length;
        final chunk = currentPackages.sublist(i, end);

        final chunkFile = await _writePackageListFileForChunk(
          deviceId,
          chunk,
          i,
        );
        final remoteChunkPath = '$_remotePackageListPath.$i';

        final pushListResult = await _adb.run([
          '-s',
          deviceId,
          'push',
          chunkFile.path,
          remoteChunkPath,
        ], timeout: _fileTransferTimeout);

        if (!pushListResult.isSuccess) {
          continue;
        }

        final result = await _adb.shell(
          deviceId,
          'CLASSPATH=$_remoteDexPath app_process /system/bin '
          'com.adbmanage.helper.PackageIconHelper '
          '$remoteChunkPath $userId',
          timeout: _metadataTimeout,
        );

        // 删除临时生成的分批包名列表文件
        unawaited(_adb.shell(deviceId, 'rm -f $remoteChunkPath'));

        if (!result.isSuccess) {
          continue;
        }

        final iconInfos = _parseIconHelperOutput(result.stdout);
        if (iconInfos.isEmpty) {
          continue;
        }

        var updatedAny = false;
        for (var j = i; j < end; j++) {
          final package = currentPackages[j];
          final iconInfo = iconInfos[package.name];
          if (iconInfo != null) {
            final iconLocalPath = await _pullIconIfNeeded(deviceId, iconInfo);
            currentPackages[j] = package.copyWith(
              label: iconInfo.label.isEmpty ? null : iconInfo.label,
              iconLocalPath: iconLocalPath,
              iconRemotePath: iconInfo.remotePath.isEmpty
                  ? null
                  : iconInfo.remotePath,
              signatureMd5: iconInfo.signatureMd5.isEmpty
                  ? null
                  : iconInfo.signatureMd5,
              firstInstallTime: iconInfo.firstInstallTime,
              lastUpdateTime: iconInfo.lastUpdateTime,
            );
            updatedAny = true;
          }
        }

        if (updatedAny) {
          yield List<AdbPackage>.from(currentPackages);
        }
      }
    } catch (_) {
      // 允许后台分批拉取失败时不抛出异常
    }
  }

  Future<File> _writePackageListFileForChunk(
    String deviceId,
    List<AdbPackage> chunk,
    int index,
  ) async {
    final dir = Directory('${Directory.systemTemp.path}/any_deck_packages');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File(
      '${dir.path}/${_safeFileSegment(deviceId)}_chunk_$index.txt',
    );
    await file.writeAsString(
      chunk.map((package) => package.name).join('\n'),
      flush: true,
    );
    return file;
  }

  Future<void> _ensureIconHelperPushed(String deviceId) async {
    final helperFile = await _writeHelperAssetToTemp();
    await _adb.shell(
      deviceId,
      'mkdir -p $_remoteBaseDir/icons',
      timeout: _quickTimeout,
    );
    await _adb.run([
      '-s',
      deviceId,
      'push',
      helperFile.path,
      _remoteDexPath,
    ], timeout: _fileTransferTimeout);
  }

  Future<File> _writeHelperAssetToTemp() async {
    final bytes = await rootBundle.load(_helperAssetPath);
    final dir = Directory('${Directory.systemTemp.path}/any_deck_helper');
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

  Future<int> _currentUserId(String deviceId) async {
    final result = await _adb.shellArgs(deviceId, [
      'am',
      'get-current-user',
    ], timeout: _quickTimeout);
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
      final signatureMd5 = parts.length > 3 ? parts[3].trim() : '';
      final firstInstallTime = parts.length > 4
          ? int.tryParse(parts[4].trim())
          : null;
      final lastUpdateTime = parts.length > 5
          ? int.tryParse(parts[5].trim())
          : null;

      infos[parts[0]] = _IconHelperInfo(
        packageName: parts[0],
        label: _decodeBase64(parts[1]),
        remotePath: parts[2],
        signatureMd5: signatureMd5,
        firstInstallTime: firstInstallTime,
        lastUpdateTime: lastUpdateTime,
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
    ], timeout: _fileTransferTimeout);
    return result.isSuccess && localFile.existsSync() ? localFile.path : null;
  }

  Directory _localIconCacheDir(String deviceId) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory(
        '$home/Library/Caches/AnyDeck/package_icons/${_safeFileSegment(deviceId)}',
      );
    }
    return Directory(
      '${Directory.systemTemp.path}/AnyDeck/package_icons/${_safeFileSegment(deviceId)}',
    );
  }

  String _safeFileSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  static const _packageSizeCommand = '''
for line in \$(pm list packages -f --user 0 2>/dev/null | sed 's/^package://'); do
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
  for line in \$(pm list packages -f --user 0 2>/dev/null | sed 's/^package://'); do
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
    return _adb.run([
      '-s',
      deviceId,
      'install',
      '-r',
      apkPath,
    ], timeout: _fileTransferTimeout);
  }

  /// 导出设备上的应用安装包到本地。
  Future<AdbResult> exportApk(
    String deviceId,
    String packageName,
    String localSavePath, {
    String? apkPath,
  }) async {
    String? path = apkPath;
    if (path == null || path.isEmpty) {
      final pathResult = await packagePath(deviceId, packageName);
      if (!pathResult.isSuccess || pathResult.stdout.isEmpty) {
        return AdbResult(exitCode: 1, stdout: '', stderr: '无法获取应用的安装路径');
      }
      final stdout = pathResult.stdout.trim();
      if (stdout.startsWith('package:')) {
        path = stdout.substring('package:'.length).trim();
      }
    }
    if (path == null || path.isEmpty) {
      return AdbResult(exitCode: 1, stdout: '', stderr: '解析安装路径失败');
    }
    return _adb.run([
      '-s',
      deviceId,
      'pull',
      path,
      localSavePath,
    ], timeout: _fileTransferTimeout);
  }

  /// 从设备卸载指定应用包。
  Future<AdbResult> uninstall(String deviceId, String packageName) {
    return _adb.run(['-s', deviceId, 'uninstall', packageName]);
  }

  /// 通过 monkey 启动应用默认入口 Activity。
  Future<AdbResult> launch(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['monkey', '-p', packageName, '1']);
  }

  /// 跳转到手机系统设置中的应用信息页面。
  Future<AdbResult> openAppInfo(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, [
      'am',
      'start',
      '-a',
      'android.settings.APPLICATION_DETAILS_SETTINGS',
      '-d',
      'package:$packageName',
    ]);
  }

  /// 强停目标应用进程，但不清除应用数据。
  Future<AdbResult> forceStop(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['am', 'force-stop', packageName]);
  }

  /// 通过 Android PackageManager 清除应用数据。
  Future<AdbResult> clearData(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['pm', 'clear', packageName]);
  }

  /// 冻结（停用）应用，使用 disable-user 无需 root 权限。
  Future<AdbResult> freezeApp(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, [
      'pm',
      'disable-user',
      '--user',
      '0',
      packageName,
    ]);
  }

  /// 解冻（启用）应用。
  Future<AdbResult> unfreezeApp(String deviceId, String packageName) {
    return _adb.shellArgs(deviceId, ['pm', 'enable', packageName]);
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

  List<_ListedPackage> _mergeListedPackages(
    List<_ListedPackage> primary,
    List<_ListedPackage> secondary,
  ) {
    final merged = <String, _ListedPackage>{};
    for (final package in primary) {
      merged[package.name] = package;
    }
    for (final package in secondary) {
      merged[package.name] = package;
    }
    return merged.values.toList(growable: false);
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
      debuggable: block.contains('DEBUGGABLE'),
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

  Future<Map<String, int>> getPackageSizeDetails(
    String deviceId,
    String packageName,
  ) async {
    final results = await Future.wait([
      _adb.shell(deviceId, 'dumpsys diskstats'),
      _adb.shellArgs(deviceId, ['dumpsys', 'package', packageName]),
    ]);

    final diskstatsOutput = results[0].isSuccess ? results[0].stdout : '';
    final packageOutput = results[1].isSuccess ? results[1].stdout : '';

    final pkgMatch = RegExp(
      r'Package Names:\s*\[(.*?)\]',
    ).firstMatch(diskstatsOutput);
    final appMatch = RegExp(
      r'App Sizes:\s*\[(.*?)\]',
    ).firstMatch(diskstatsOutput);
    final dataMatch = RegExp(
      r'App Data Sizes:\s*\[(.*?)\]',
    ).firstMatch(diskstatsOutput);
    final cacheMatch = RegExp(
      r'Cache Sizes:\s*\[(.*?)\]',
    ).firstMatch(diskstatsOutput);

    int appSize = 0;
    int dataSize = 0;
    int cacheSize = 0;

    if (pkgMatch != null &&
        appMatch != null &&
        dataMatch != null &&
        cacheMatch != null) {
      final pkgs = pkgMatch
          .group(1)!
          .split(',')
          .map((p) => p.trim().replaceAll('"', ''))
          .toList();
      final index = pkgs.indexOf(packageName);
      if (index != -1) {
        final appSizes = appMatch
            .group(1)!
            .split(',')
            .map((s) => int.tryParse(s.trim()) ?? 0)
            .toList();
        final dataSizes = dataMatch
            .group(1)!
            .split(',')
            .map((s) => int.tryParse(s.trim()) ?? 0)
            .toList();
        final cacheSizes = cacheMatch
            .group(1)!
            .split(',')
            .map((s) => int.tryParse(s.trim()) ?? 0)
            .toList();

        if (index < appSizes.length) appSize = appSizes[index];
        if (index < dataSizes.length) dataSize = dataSizes[index];
        if (index < cacheSizes.length) cacheSize = cacheSizes[index];
      }
    }

    final odexMatch = RegExp(
      r'base\.odex:\s*(\d+)\s*(Kb|Mb|Bytes|B|KB|MB)',
      caseSensitive: false,
    ).firstMatch(packageOutput);
    final vdexMatch = RegExp(
      r'base\.vdex:\s*(\d+)\s*(Kb|Mb|Bytes|B|KB|MB)',
      caseSensitive: false,
    ).firstMatch(packageOutput);

    int compiledSize = 0;
    if (odexMatch != null) {
      compiledSize += _parseSizeString(
        odexMatch.group(1)!,
        odexMatch.group(2)!,
      );
    }
    if (vdexMatch != null) {
      compiledSize += _parseSizeString(
        vdexMatch.group(1)!,
        vdexMatch.group(2)!,
      );
    }

    return {
      'appSize': appSize + compiledSize,
      'dataSize': dataSize,
      'cacheSize': cacheSize,
    };
  }

  int _parseSizeString(String value, String unit) {
    final val = int.tryParse(value) ?? 0;
    switch (unit.toLowerCase()) {
      case 'kb':
      case 'k':
        return val * 1024;
      case 'mb':
      case 'm':
        return val * 1024 * 1024;
      case 'gb':
      case 'g':
        return val * 1024 * 1024 * 1024;
      default:
        return val;
    }
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
    this.debuggable = false,
  });

  final String? label;
  final String? versionName;
  final String? versionCode;
  final int? minSdk;
  final int? targetSdk;
  final int? maxSdk;
  final bool system;
  final bool debuggable;
}

class _IconHelperInfo {
  const _IconHelperInfo({
    required this.packageName,
    required this.label,
    required this.remotePath,
    this.signatureMd5 = '',
    this.firstInstallTime,
    this.lastUpdateTime,
  });

  final String packageName;
  final String label;
  final String remotePath;
  final String signatureMd5;
  final int? firstInstallTime;
  final int? lastUpdateTime;
}
