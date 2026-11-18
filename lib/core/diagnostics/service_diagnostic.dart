/// 全局服务检查范围；稳定标识用于面板展开和按服务聚合结果。
enum DiagnosticService {
  adb,
  hdc,
  ios,
  mirror,
  airplay,
  dlna,
  transfer,
  mcp,
  virtualCamera,
  lanShare,
  notifications,
  deviceSessions,
}

/// 区分正常停用、平台不支持和真正故障，避免把未启用服务计为异常。
enum ServiceDiagnosticStatus {
  notChecked,
  checking,
  running,
  ready,
  disabled,
  missing,
  error,
  permissionRequired,
  unsupported,
  unknown;

  bool get needsAttention =>
      this == missing || this == error || this == permissionRequired;
}

/// 诊断快照中的技术字段；标签走 l10n，值仅来自当前真实检测。
class DiagnosticDetail {
  const DiagnosticDetail(this.labelKey, this.value);
  final String labelKey;
  final String value;
}

/// 单项诊断结果，不持有服务、凭据、进程或设备会话。
class ServiceDiagnostic {
  const ServiceDiagnostic({
    required this.service,
    this.status = ServiceDiagnosticStatus.notChecked,
    this.reasonKey = 'diagnosticsNotCheckedReason',
    this.adviceKey = 'diagnosticsRunAdvice',
    this.details = const [],
  });

  final DiagnosticService service;
  final ServiceDiagnosticStatus status;
  final String reasonKey;
  final String adviceKey;
  final List<DiagnosticDetail> details;
  String get titleKey => 'diagnosticsService${service.name}';
  String get impactKey => 'diagnosticsImpact${service.name}';
  bool get needsAttention => status.needsAttention;
}

/// 一轮检查的不可变结果；时间表示快照时刻，不宣称实时持续监控。
class ServiceDiagnosticsState {
  const ServiceDiagnosticsState({
    required this.entries,
    this.isChecking = false,
    this.checkedAt,
  });

  factory ServiceDiagnosticsState.initial() => ServiceDiagnosticsState(
    entries: [
      for (final service in DiagnosticService.values)
        ServiceDiagnostic(service: service),
    ],
  );

  final List<ServiceDiagnostic> entries;
  final bool isChecking;
  final DateTime? checkedAt;
  int get issueCount => entries.where((item) => item.needsAttention).length;

  /// 按固定服务顺序稳定排序，故障与待授权项优先展示。
  List<ServiceDiagnostic> get orderedEntries => [...entries]
    ..sort((a, b) {
      final priority = (b.needsAttention ? 1 : 0) - (a.needsAttention ? 1 : 0);
      return priority != 0
          ? priority
          : a.service.index.compareTo(b.service.index);
    });
}
