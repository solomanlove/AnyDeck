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

  /// 探针执行期间展示的占位结果，实际工具忙碌时也可能返回 checking 状态。
  const ServiceDiagnostic.checking(DiagnosticService service)
    : this(
        service: service,
        status: ServiceDiagnosticStatus.checking,
        reasonKey: 'diagnosticsCheckingReason',
      );

  final DiagnosticService service;
  final ServiceDiagnosticStatus status;
  final String reasonKey;
  final String adviceKey;
  final List<DiagnosticDetail> details;
  String get titleKey => 'diagnosticsService${service.name}';
  String get impactKey => 'diagnosticsImpact${service.name}';
  bool get needsAttention => status.needsAttention;
}

/// 各服务的最近诊断快照；时间表示最近一次检测完成的时刻。
class ServiceDiagnosticsState {
  const ServiceDiagnosticsState({
    required this.entries,
    bool isChecking = false,
    List<DiagnosticService> checkingServices = const [],
    this.checkedAt,
  }) : _checkingServices = isChecking
           ? DiagnosticService.values
           : checkingServices;

  factory ServiceDiagnosticsState.initial() => ServiceDiagnosticsState(
    entries: [
      for (final service in DiagnosticService.values)
        ServiceDiagnostic(service: service),
    ],
  );

  final List<ServiceDiagnostic> entries;
  final List<DiagnosticService> _checkingServices;
  final DateTime? checkedAt;
  bool get isChecking => _checkingServices.isNotEmpty;
  bool isCheckingService(DiagnosticService service) =>
      _checkingServices.contains(service);
  int get checkedCount => entries
      .where(
        (item) =>
            item.status != ServiceDiagnosticStatus.notChecked &&
            !isCheckingService(item.service),
      )
      .length;
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
