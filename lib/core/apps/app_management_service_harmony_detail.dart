part of 'app_management_service.dart';

/// HarmonyOS 应用详情只通过 HDC/BM 获取，禁止回退到 Android ADB Helper。
extension HarmonyAppDetailService on AppManagementService {
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
