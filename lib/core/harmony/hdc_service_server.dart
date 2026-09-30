import '../adb/adb_result.dart';
import 'hdc_service.dart';

/// HDC 服务端生命周期管理扩展
extension HdcServiceServerExtension on HdcService {
  /// 终止并重新启动 HDC 服务端。
  Future<AdbResult> restartServer() async {
    final killResult = await run(['kill', '-r']);
    if (!killResult.isSuccess) {
      await run(['kill']);
      return run(['start']);
    }
    return killResult;
  }
}
