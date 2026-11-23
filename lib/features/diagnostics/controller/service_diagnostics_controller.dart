import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/service_diagnostic.dart';
import 'service_diagnostic_checks.dart';

/// 单项检查可独立替换，测试无需连接手机或启用系统服务。
final serviceDiagnosticChecksProvider =
    Provider<Map<DiagnosticService, DiagnosticCheck>>(
      createServiceDiagnosticChecks,
    );

/// 全局快照在关闭面板后保留；入口常驻不产生轮询或自动检查。
final serviceDiagnosticsProvider =
    NotifierProvider<ServiceDiagnosticsController, ServiceDiagnosticsState>(
      ServiceDiagnosticsController.new,
    );

/// 执行单项或全量只读诊断；重叠请求共用同一服务的探针。
class ServiceDiagnosticsController extends Notifier<ServiceDiagnosticsState> {
  Future<void>? _pendingAll;
  final _pendingSingles = <DiagnosticService, Future<ServiceDiagnostic>>{};

  @override
  ServiceDiagnosticsState build() => ServiceDiagnosticsState.initial();

  /// 全量检查接管在途单项，待所有服务完成后一次性发布完整快照。
  Future<void> run() {
    final pending = _pendingAll;
    if (pending != null) return pending;
    final checks = ref.read(serviceDiagnosticChecksProvider);
    final task =
        Future.wait([
          for (final service in DiagnosticService.values)
            _pendingSingles[service] ?? _check(service, checks[service]),
        ]).then<void>((entries) {
          _pendingAll = null;
          if (!ref.mounted) return;
          state = ServiceDiagnosticsState(
            entries: List.unmodifiable(entries),
            checkedAt: DateTime.now(),
          );
        });
    _pendingAll = task;
    state = ServiceDiagnosticsState(
      entries: [
        for (final service in DiagnosticService.values)
          ServiceDiagnostic.checking(service),
      ],
      isChecking: true,
    );
    return task;
  }

  /// 只运行指定服务；其他服务的结果与正在执行的检查分别保留。
  Future<void> runSingle(DiagnosticService service) {
    final pending = _pendingAll ?? _pendingSingles[service];
    if (pending != null) return pending;
    final check = ref.read(serviceDiagnosticChecksProvider)[service];
    final task = _check(service, check).then((result) {
      _pendingSingles.remove(service);
      if (ref.mounted && _pendingAll == null) {
        _publishSingle(result, DateTime.now());
      }
      return result;
    });
    _pendingSingles[service] = task;
    _publishSingle(ServiceDiagnostic.checking(service), state.checkedAt);
    return task;
  }

  void _publishSingle(ServiceDiagnostic result, DateTime? checkedAt) {
    state = ServiceDiagnosticsState(
      entries: List.unmodifiable([
        for (final entry in state.entries)
          if (entry.service == result.service) result else entry,
      ]),
      checkingServices: List.unmodifiable(_pendingSingles.keys),
      checkedAt: checkedAt,
    );
  }

  Future<ServiceDiagnostic> _check(
    DiagnosticService service,
    DiagnosticCheck? check,
  ) async {
    if (check == null) {
      return diagnosticResult(
        service,
        ServiceDiagnosticStatus.unknown,
        reason: 'diagnosticsNoStatus',
      );
    }
    try {
      return await check().timeout(const Duration(seconds: 15));
    } on MissingPluginException {
      return diagnosticResult(
        service,
        ServiceDiagnosticStatus.missing,
        reason: 'diagnosticsNativeMissing',
      );
    } on FileSystemException catch (error) {
      return diagnosticResult(
        service,
        ServiceDiagnosticStatus.missing,
        details: [diagnosticErrorDetail(error)],
      );
    } on ProcessException catch (error) {
      return diagnosticResult(
        service,
        error.errorCode == 2
            ? ServiceDiagnosticStatus.missing
            : ServiceDiagnosticStatus.error,
        details: [diagnosticErrorDetail(error)],
      );
    } catch (error) {
      return diagnosticResult(
        service,
        ServiceDiagnosticStatus.error,
        reason: error is TimeoutException ? 'diagnosticsTimeout' : null,
        details: [diagnosticErrorDetail(error)],
      );
    }
  }
}
