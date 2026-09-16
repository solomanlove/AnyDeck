// 鸿蒙应用图标通过华为应用市场在线 API 获取（参考 liriliri/echo 实现）。
// 设备端因权限限制无法直接读取图标文件，改用在线 API 用 bundleName 查询。
// 以下文件系统方案（方案 A/B）保留供未来离线场景复用。
// ignore_for_file: unused_element, unused_element_parameter
part of 'app_management_service.dart';

/// 鸿蒙应用图标提取（方案 A：bm dump -n → codePath → module.json → hdc file recv；
/// 降级方案 B：拉 hap 回本地 unzip 解压）。
///
/// 鸿蒙资源是文件式（`resources/base/media/app_icon.png`），不像 Android 的
/// resources.arsc 二进制，因此无需 app_process/dex helper，纯文件操作即可。
/// 字段名按 OpenHarmony 多版本兼容候选（codePath/installationDir/codeDir），
/// 需真机验证后收口。

/// 解析 `bm dump -n <bundle>` 输出中的安装目录字段。
String? _parseHarmonyCodePath(String output) {
  for (final key in const [
    'codePath',
    'installationDir',
    'codeDir',
    'hapPath',
  ]) {
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('$key:') || trimmed.startsWith('$key :')) {
        final value = trimmed.split(':').skip(1).join(':').trim();
        if (value.isNotEmpty && !value.contains(' ')) {
          return value;
        }
      }
    }
  }
  return null;
}

/// 解析 module.json 中主 Ability 的图标资源引用（如 `$media:app_icon`）。
String? _parseHarmonyIconResource(String moduleJson) {
  try {
    final decoded = jsonDecode(moduleJson) as Map<String, dynamic>;
    final module = decoded['module'] as Map<String, dynamic>?;
    final abilities = module?['abilities'] as List<dynamic>?;
    if (abilities == null || abilities.isEmpty) return null;
    for (final ability in abilities) {
      if (ability is! Map<String, dynamic>) continue;
      final icon = ability['iconResource'] as String?;
      if (icon != null && icon.isNotEmpty) return icon;
    }
  } catch (_) {}
  return null;
}

/// 将资源引用 `$media:app_icon` 转为资源文件名 `app_icon`。
String? _harmonyResourceFileName(String resourceRef) {
  final colon = resourceRef.indexOf(':');
  if (colon <= 0 || colon >= resourceRef.length - 1) return null;
  return resourceRef.substring(colon + 1).trim();
}

/// 提取单个鸿蒙应用的图标到本地缓存，返回本地路径；失败返回 null。
Future<String?> _readHarmonyPackageIcon(
  AppManagementService service,
  String deviceId,
  String bundleName, {
  String? canonicalId,
  List<String> fallbackKeys = const [],
}) async {
  final hdc = service._hdc;
  if (hdc == null) return null;

  final cacheDir = service._localIconCacheDir(canonicalId ?? deviceId);
  if (!cacheDir.existsSync()) {
    cacheDir.createSync(recursive: true);
  }
  final localFile = File('${cacheDir.path}/${service._safeFileSegment(bundleName)}.png');
  if (localFile.existsSync() && localFile.lengthSync() > 0) {
    return localFile.path;
  }

  try {
    // 方案 A：bm dump -n → codePath → cat module.json → file recv
    final dump = await hdc.shell(
      deviceId,
      'bm dump -n $bundleName',
      timeout: AppManagementService._metadataTimeout,
    );
    if (!dump.isSuccess) return null;
    final codePath = _parseHarmonyCodePath(dump.stdout);
    if (codePath == null) return null;

    final iconPath = await _resolveHarmonyIconPath(service, hdc, deviceId, codePath, bundleName);
    if (iconPath != null) {
      final recv = await hdc.fileRecv(
        deviceId,
        iconPath,
        localFile.path,
        timeout: AppManagementService._fileTransferTimeout,
      );
      if (recv.isSuccess && localFile.existsSync() && localFile.lengthSync() > 0) {
        return localFile.path;
      }
    }

    // 降级方案 B：codePath 可能是 hap 文件或含 hap 的目录，拉回本地解压
    return await _readHarmonyIconFromHap(
      service,
      hdc,
      deviceId,
      codePath,
      bundleName,
      localFile,
    );
  } catch (_) {
    return null;
  }
}

/// 在 codePath 下定位图标文件路径（方案 A）。
Future<String?> _resolveHarmonyIconPath(
  AppManagementService service,
  HdcService hdc,
  String deviceId,
  String codePath,
  String bundleName,
) async {
  // codePath 可能是目录（解压后的 hap 内容）或 hap 文件本身。
  // 先尝试直接 cat module.json（解压目录情况）。
  final moduleResult = await hdc.shell(
    deviceId,
    'cat $codePath/module.json',
    timeout: AppManagementService._quickTimeout,
  );
  if (!moduleResult.isSuccess || moduleResult.stdout.trim().isEmpty) {
    // 可能在 entry/ 子目录
    final entryResult = await hdc.shell(
      deviceId,
      'cat $codePath/entry/module.json',
      timeout: AppManagementService._quickTimeout,
    );
    if (!entryResult.isSuccess || entryResult.stdout.trim().isEmpty) {
      return null;
    }
    return _resolveIconFileFromModule(
      service,
      hdc,
      deviceId,
      entryResult.stdout,
      '$codePath/entry',
    );
  }
  return _resolveIconFileFromModule(
    service,
    hdc,
    deviceId,
    moduleResult.stdout,
    codePath,
  );
}

/// 从 module.json 内容解析图标资源，在 baseDir 下定位实际文件（png/webp）。
Future<String?> _resolveIconFileFromModule(
  AppManagementService service,
  HdcService hdc,
  String deviceId,
  String moduleJson,
  String baseDir,
) async {
  final iconRef = _parseHarmonyIconResource(moduleJson);
  if (iconRef == null) return null;
  final fileName = _harmonyResourceFileName(iconRef);
  if (fileName == null) return null;

  // 鸿蒙资源目录：resources/base/media/（默认）或限定词目录。
  // 尝试 png 与 webp 两种扩展名。
  for (final subDir in const [
    'resources/base/media',
    'resources/phone/media',
    'resources/default/media',
  ]) {
    for (final ext in const ['png', 'webp']) {
      final candidate = '$baseDir/$subDir/$fileName.$ext';
      final check = await hdc.shell(
        deviceId,
        'test -f "$candidate" && echo ok',
        timeout: AppManagementService._quickTimeout,
      );
      if (check.isSuccess && check.stdout.trim() == 'ok') {
        return candidate;
      }
    }
  }
  return null;
}

/// 降级方案 B：从 hap 文件提取图标。拉回本地 unzip 后读 resources/base/media/。
Future<String?> _readHarmonyIconFromHap(
  AppManagementService service,
  HdcService hdc,
  String deviceId,
  String codePath,
  String bundleName,
  File targetPng,
) async {
  // 定位 hap 文件：codePath 本身可能是 hap，或目录下含 *.hap
  String? hapRemotePath;
  if (codePath.endsWith('.hap')) {
    final check = await hdc.shell(
      deviceId,
      'test -f "$codePath" && echo ok',
      timeout: AppManagementService._quickTimeout,
    );
    if (check.isSuccess && check.stdout.trim() == 'ok') {
      hapRemotePath = codePath;
    }
  } else {
    final ls = await hdc.shell(
      deviceId,
      'ls $codePath/*.hap 2>/dev/null | head -1',
      timeout: AppManagementService._quickTimeout,
    );
    final line = ls.stdout.split('\n').firstWhere(
      (l) => l.trim().isNotEmpty && l.trim().endsWith('.hap'),
      orElse: () => '',
    );
    if (line.isNotEmpty) hapRemotePath = line.trim();
  }
  if (hapRemotePath == null) return null;

  // 拉回 hap 到临时目录
  final tempDir = Directory('${Directory.systemTemp.path}/any_deck_hap');
  if (!tempDir.existsSync()) {
    tempDir.createSync(recursive: true);
  }
  final localHap = File('${tempDir.path}/${service._safeFileSegment(bundleName)}.hap');
  final recv = await hdc.fileRecv(
    deviceId,
    hapRemotePath,
    localHap.path,
    timeout: AppManagementService._fileTransferTimeout,
  );
  if (!recv.isSuccess || !localHap.existsSync()) return null;

  // 本地 unzip 解压 module.json + resources/media
  final extractDir = Directory('${tempDir.path}/${service._safeFileSegment(bundleName)}');
  if (extractDir.existsSync()) {
    extractDir.deleteSync(recursive: true);
  }
  extractDir.createSync(recursive: true);
  try {
    final unzip = await Process.run(
      'unzip',
      ['-o', '-q', localHap.path, 'module.json', '*/module.json', 'resources/*', '*/resources/*', '-d', extractDir.path],
    );
    if (unzip.exitCode != 0) return null;
  } catch (_) {
    return null;
  }

  // 在解压目录中查找图标
  final iconFile = _findHarmonyIconInDir(extractDir);
  if (iconFile != null) {
    try {
      iconFile.copySync(targetPng.path);
      return targetPng.path;
    } catch (_) {}
  }
  return null;
}

/// 在本地解压目录中递归查找 resources/*/media/app_icon.{png,webp}。
File? _findHarmonyIconInDir(Directory root) {
  // 先读 module.json 拿 iconResource
  File? moduleJson;
  for (final entity in root.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('module.json')) {
      moduleJson = entity;
      break;
    }
  }
  if (moduleJson == null) return null;
  String? iconRef;
  try {
    iconRef = _parseHarmonyIconResource(moduleJson.readAsStringSync());
  } catch (_) {}
  if (iconRef == null) return null;
  final fileName = _harmonyResourceFileName(iconRef);
  if (fileName == null) return null;

  for (final entity in root.listSync(recursive: true)) {
    if (entity is File) {
      final name = entity.path.split('/').last;
      if (name.startsWith(fileName) &&
          (name.endsWith('.png') || name.endsWith('.webp')) &&
          entity.path.contains('media')) {
        return entity;
      }
    }
  }
  return null;
}

/// 华为应用市场在线应用信息 API。
const _harmonyAppInfoUrl =
    'https://web-drcn.hispace.dbankcloud.com/edge/webedge/appinfo';

/// 判断是否为鸿蒙系统应用：包名以 `com.huawei` 或 `com.ohos` 开头。
bool _isHarmonySystemBundle(String bundleName) {
  return bundleName.startsWith('com.huawei') ||
      bundleName.startsWith('com.ohos');
}

/// 华为应用市场在线查询结果。
class _HarmonyOnlineAppInfo {
  final String? label;
  final String? iconUrl;
  _HarmonyOnlineAppInfo({this.label, this.iconUrl});
}

/// 在线查询缓存（进程内），避免重复请求。
final Map<String, _HarmonyOnlineAppInfo> _harmonyOnlineCache = {};

/// 通过华为应用市场 API 查询应用名称和图标 URL。
Future<_HarmonyOnlineAppInfo> _fetchHarmonyOnlineAppInfo(
  String bundleName,
) async {
  if (_harmonyOnlineCache.containsKey(bundleName)) {
    return _harmonyOnlineCache[bundleName]!;
  }
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final request = await client.postUrl(Uri.parse(_harmonyAppInfoUrl));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'pkgName': bundleName,
      'appId': bundleName,
      'locale': 'zh_CN',
      'countryCode': 'CN',
      'orderApp': 1,
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    if (response.statusCode != 200) {
      final info = _HarmonyOnlineAppInfo();
      _harmonyOnlineCache[bundleName] = info;
      return info;
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    final info = _HarmonyOnlineAppInfo(
      label: data['name'] as String?,
      iconUrl: data['icon'] as String?,
    );
    _harmonyOnlineCache[bundleName] = info;
    return info;
  } catch (_) {
    final info = _HarmonyOnlineAppInfo();
    _harmonyOnlineCache[bundleName] = info;
    return info;
  }
}

/// 下载图标 URL 到本地缓存文件，返回本地路径；失败返回 null。
Future<String?> _downloadHarmonyIcon(
  String iconUrl,
  File localFile,
) async {
  if (localFile.existsSync() && localFile.lengthSync() > 0) {
    return localFile.path;
  }
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final request = await client.getUrl(Uri.parse(iconUrl));
    final response = await request.close();
    if (response.statusCode != 200) {
      client.close();
      return null;
    }
    final bytes = await response.expand((chunk) => chunk).toList();
    client.close();
    if (bytes.isEmpty) return null;
    localFile.writeAsBytesSync(bytes);
    return localFile.path;
  } catch (_) {
    return null;
  }
}

/// 批量为鸿蒙应用列表补充图标（通过华为应用市场在线 API）。
///
/// 参考 liriliri/echo 实现：用 bundleName 调用华为应用市场 appinfo API，
/// 返回应用名称和图标 URL。仅对非系统应用查询，系统应用用 label 占位。
/// 在线 API 不可用或应用未上架时静默跳过，不影响列表展示。
Stream<List<AdbPackage>> _enrichHarmonyPackageIcons(
  AppManagementService service,
  String deviceId,
  List<AdbPackage> packages, {
  String? canonicalId,
  List<String> fallbackKeys = const [],
  PackageRefreshCallback? onProgress,
  bool Function()? isActive,
}) async* {
  if (packages.isEmpty) return;
  bool active() => isActive?.call() ?? true;
  final current = List<AdbPackage>.from(packages);
  final cacheDir = service._localIconCacheDir(canonicalId ?? deviceId);
  if (!cacheDir.existsSync()) {
    cacheDir.createSync(recursive: true);
  }
  var processed = 0;
  const chunkSize = 20;
  for (var i = 0; i < current.length; i += chunkSize) {
    if (!active()) return;
    final end = (i + chunkSize).clamp(0, current.length);
    var updatedAny = false;
    for (var j = i; j < end; j++) {
      if (!active()) return;
      final pkg = current[j];
      if (_isHarmonySystemBundle(pkg.name)) {
        processed++;
        continue;
      }
      try {
        final onlineInfo = await _fetchHarmonyOnlineAppInfo(pkg.name);
        String? iconLocalPath;
        if (onlineInfo.iconUrl != null && onlineInfo.iconUrl!.isNotEmpty) {
          final localFile = File(
            '${cacheDir.path}/${service._safeFileSegment(pkg.name)}.png',
          );
          iconLocalPath = await _downloadHarmonyIcon(
            onlineInfo.iconUrl!,
            localFile,
          );
        }
        current[j] = pkg.copyWith(
          label: onlineInfo.label?.isNotEmpty == true
              ? onlineInfo.label
              : pkg.label,
          iconLocalPath: iconLocalPath,
        );
        if (iconLocalPath != null || onlineInfo.label != null) {
          updatedAny = true;
        }
      } catch (_) {}
      processed++;
    }
    if (updatedAny) {
      yield List<AdbPackage>.from(current);
    }
    onProgress?.call(PackageRefreshProgress(
      stage: PackageRefreshStage.enriching,
      processed: processed,
      total: current.length,
    ));
  }
  yield List<AdbPackage>.from(current);
}
