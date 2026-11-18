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

/// 显式执行全量只读诊断；并发点击共用同一轮，单项失败不阻断其余服务。
class ServiceDiagnosticsController extends Notifier<ServiceDiagnosticsState> {
  Future<void>? _pending;

  @override
  ServiceDiagnosticsState build() => ServiceDiagnosticsState.initial();

  Future<void> run() => _pending ??= _run().whenComplete(() => _pending = null);

  Future<void> _run() async {
    final checks = ref.read(serviceDiagnosticChecksProvider);
    state = ServiceDiagnosticsState(
      entries: [
        for (final service in DiagnosticService.values)
          ServiceDiagnostic(
            service: service,
            status: ServiceDiagnosticStatus.checking,
            reasonKey: 'diagnosticsCheckingReason',
          ),
      ],
      isChecking: true,
    );
    final entries = await Future.wait([
      for (final service in DiagnosticService.values)
        _check(service, checks[service]),
    ]);
    if (!ref.mounted) return;
    state = ServiceDiagnosticsState(
      entries: List.unmodifiable(entries),
      checkedAt: DateTime.now(),
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
