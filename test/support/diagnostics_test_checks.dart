import 'package:any_deck/core/diagnostics/service_diagnostic.dart';
import 'package:any_deck/core/environment/connection_environment_service.dart';
import 'package:any_deck/features/diagnostics/controller/service_diagnostic_checks.dart';

/// 保留真实诊断控制器与 UI，仅将 CLI/权限探针替换为可计数的内存结果。
class DiagnosticsTestChecks {
  int calls = 0;

  Map<DiagnosticService, DiagnosticCheck> get checks => {
    for (final service in DiagnosticService.values)
      service: () async {
        calls++;
        return ServiceDiagnostic(
          service: service,
          status: service == DiagnosticService.hdc
              ? ServiceDiagnosticStatus.missing
              : ServiceDiagnosticStatus.ready,
        );
      },
  };
}

/// 安装指引展示当前环境快照，不在 Widget test 内启动新的 CLI 检查。
class DiagnosticsTestEnvironment extends ConnectionEnvironmentNotifier {
  @override
  Future<Map<TargetPlatformType, PlatformEnvironmentInfo>> checkAll() async =>
      state;
}
