import '../adb/adb_result.dart';
import '../adb/adb_service.dart';

/// 当前前台应用信息，用于投屏窗口长按返回键快速强停。
class ForegroundAppInfo {
  const ForegroundAppInfo({
    required this.packageName,
    required this.displayName,
    required this.isHome,
  });

  final String packageName;
  final String displayName;
  final bool isHome;
}

/// 读取前台应用并执行包级控制，避免 UI 层重复拼接 adb 命令。
class ForegroundAppService {
  ForegroundAppService(this._adb);

  final AdbService _adb;

  /// 查询当前前台应用，桌面场景统一返回“桌面”。
  Future<ForegroundAppInfo> foregroundApp(String deviceId) async {
    final focusResult = await _adb.shell(
      deviceId,
      'dumpsys window | grep mCurrentFocus',
      timeout: const Duration(seconds: 5),
    );
    if (!focusResult.isSuccess || focusResult.stdout.trim().isEmpty) {
      throw Exception(focusResult.message);
    }

    final lines = focusResult.stdout.split('\n');
    final packages = <String>[];
    for (final line in lines) {
      final pkg = _parsePackageFromFocusLine(line.trim());
      if (pkg.isNotEmpty && !packages.contains(pkg)) {
        packages.add(pkg);
      }
    }

    if (packages.isEmpty) {
      return const ForegroundAppInfo(
        packageName: '',
        displayName: '桌面',
        isHome: true,
      );
    }

    String selectedPackage = '';
    for (final pkg in packages.reversed) {
      if (await _isHomePackage(deviceId, pkg)) {
        continue;
      }
      selectedPackage = pkg;
      break;
    }

    if (selectedPackage.isEmpty) {
      return const ForegroundAppInfo(
        packageName: '',
        displayName: '桌面',
        isHome: true,
      );
    }

    final displayName = await _readApplicationLabel(deviceId, selectedPackage);
    return ForegroundAppInfo(
      packageName: selectedPackage,
      displayName: displayName.isEmpty ? selectedPackage : displayName,
      isHome: false,
    );
  }

  /// 强停指定应用包名。
  Future<AdbResult> forceStopPackage(String deviceId, String packageName) =>
      _adb.shellArgs(deviceId, [
        'am',
        'force-stop',
        packageName,
      ], timeout: const Duration(seconds: 8));

  String _parsePackageFromFocusLine(String focusLine) {
    final slashIndex = focusLine.indexOf('/');
    if (slashIndex == -1) {
      return '';
    }
    final openBraceIndex = focusLine.lastIndexOf('{', slashIndex);
    final startSearch = openBraceIndex != -1 ? openBraceIndex + 1 : 0;
    final prefix = focusLine.substring(startSearch, slashIndex);
    final parts = prefix.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.last;
  }

  Future<bool> _isHomePackage(String deviceId, String packageName) async {
    const knownHomePackages = {
      'com.android.launcher',
      'com.android.launcher2',
      'com.android.launcher3',
      'com.google.android.apps.nexuslauncher',
      'com.miui.home',
      'com.sec.android.app.launcher',
      'com.huawei.android.launcher',
      'com.oppo.launcher',
      'com.coloros.launcher',
      'com.vivo.launcher',
      'com.realme.launcher',
      'com.oneplus.launcher',
    };
    if (knownHomePackages.contains(packageName)) {
      return true;
    }

    final result = await _adb.shell(
      deviceId,
      'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME',
      timeout: const Duration(seconds: 5),
    );
    return result.isSuccess && result.stdout.contains(packageName);
  }

  Future<String> _readApplicationLabel(
    String deviceId,
    String packageName,
  ) async {
    final result = await _adb.shell(
      deviceId,
      'dumpsys package $packageName | grep -m 1 "application-label"',
      timeout: const Duration(seconds: 5),
    );
    if (!result.isSuccess || result.stdout.trim().isEmpty) {
      return '';
    }

    final line = result.stdout.trim();
    final quoted = RegExp(
      r"application-label(?:-[^:]+)?:'([^']*)'",
    ).firstMatch(line);
    if (quoted != null) {
      return quoted.group(1)?.trim() ?? '';
    }

    final unquoted = RegExp(
      r'application-label(?:-[^:]+)?:(.+)$',
    ).firstMatch(line);
    return unquoted?.group(1)?.trim() ?? '';
  }
}
