part of 'app_management_service.dart';

/// HarmonyOS 应用详情只通过 HDC/BM 获取，禁止回退到 Android ADB Helper。
extension HarmonyAppDetailService on AppManagementService {
  /// 逐包补齐列表中的版本、安装时间与当前 HDC 权限可读取的安装目录大小。
  Future<AdbPackage?> getHarmonyPackageSummary(
    String deviceId,
    AdbPackage package,
  ) async {
    final hdc = _hdc;
    final bundleName = package.name;
    if (hdc == null ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9_.]{6,127}$').hasMatch(bundleName)) {
      return null;
    }
    final result = await hdc.shell(
      deviceId,
      'bm dump -n $bundleName',
      timeout: AppManagementService._metadataTimeout,
    );
    if (!result.isSuccess) return null;

    try {
      final detail = HarmonyAppDetailParser.parse(result.stdout);
      if (detail.bundleName != bundleName) return null;
      int? storageBytes;
      var storagePermissionDenied = false;
      final codePath = detail.codePath;
      if (codePath.startsWith('/data/app/') &&
          RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(codePath) &&
          !codePath.contains('..')) {
        try {
          final sizeResult = await hdc.shell(
            deviceId,
            'du -sk $codePath 2>&1',
            timeout: AppManagementService._metadataTimeout,
          );
          final output = '${sizeResult.stdout}\n${sizeResult.stderr}';
          storagePermissionDenied = output.toLowerCase().contains('permission denied');
          final kilobytes = int.tryParse(
            RegExp(r'^(\d+)\s', multiLine: true).firstMatch(output)?.group(1) ?? '',
          );
          if (!storagePermissionDenied && kilobytes != null) {
            storageBytes = kilobytes * 1024;
          }
        } catch (_) {
          // 大小读取失败不影响版本与安装时间的展示。
        }
      }
      return package.copyWith(
        versionName: detail.versionName.isEmpty ? null : detail.versionName,
        versionCode: detail.versionCode <= 0 ? null : '${detail.versionCode}',
        targetSdk: detail.targetApiVersion <= 0 ? null : detail.targetApiVersion,
        firstInstallTime: detail.installTime <= 0 ? null : detail.installTime,
        storageBytes: storageBytes,
        storagePermissionDenied: storagePermissionDenied,
      );
    } on FormatException {
      return null;
    }
  }

  Future<HarmonyAppDetail> getHarmonyPackageDetailedInfo(
    String deviceId,
    String bundleName,
  ) async {
    final hdc = _hdc;
    if (hdc == null) {
      throw const HarmonyAppAnalysisUnsupportedException(
        'HDC 服务不可用，无法分析 HarmonyOS 应用',
      );
    }
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.]{6,127}$').hasMatch(bundleName)) {
      throw const HarmonyAppAnalysisUnsupportedException(
        'bundleName 格式无效，已阻止执行分析命令',
      );
    }

    final result = await hdc.shell(
      deviceId,
      'bm dump -n $bundleName',
      timeout: AppManagementService._metadataTimeout,
    );
    if (!result.isSuccess || result.stdout.trim().isEmpty) {
      throw HarmonyAppAnalysisUnsupportedException(
        result.message.trim().isEmpty
            ? '当前设备或应用不支持 bm dump 分析'
            : result.message.trim(),
      );
    }

    try {
      return HarmonyAppDetailParser.parse(result.stdout);
    } on FormatException catch (error) {
      throw HarmonyAppAnalysisUnsupportedException(error.message.toString());
    }
  }
}
