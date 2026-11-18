import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/build_features.dart';
import '../../../core/airplay/airplay_server_service.dart';
import '../../../core/airplay/airplay_server_state.dart';
import '../../../core/diagnostics/service_diagnostic.dart';
import '../../../core/dlna/dlna_renderer_service.dart';
import '../../../core/environment/connection_environment_service.dart';
import '../../../core/logging/app_log_recorder.dart';
import '../../../core/nearby_share/harmony_share_service.dart';
import '../../../core/nearby_share/share_core_client.dart';
import '../../../core/process/bounded_process.dart';
import '../../../core/process/tool_path_resolver.dart';
import '../../../core/scrcpy/rust_device_bridge.dart';
import '../../../core/virtual_camera/virtual_camera_state.dart';
import '../../mcp/controller/mcp_server_controller.dart';
import 'service_session_checks.dart';

typedef DiagnosticCheck = Future<ServiceDiagnostic> Function();

/// 与主窗口入口共用编译期开关；可注入以验证未包含私有组件的构建。
final diagnosticShareCoreEnabledProvider = Provider<bool>(
  (ref) => AnyDeckBuildFeatures.shareCore,
);

/// 将既有真实能力适配为只读检查；不启动接收、投屏、传感器或授权流程。
Map<DiagnosticService, DiagnosticCheck> createServiceDiagnosticChecks(Ref ref) {
  final tools = ConnectionEnvironmentService();
  final sessions = ServiceSessionChecks(ref);
  return {
    DiagnosticService.adb: () async => diagnosticForPlatformTool(
      DiagnosticService.adb,
      await tools.checkAndroidEnvironment(),
    ),
    DiagnosticService.hdc: () async => diagnosticForPlatformTool(
      DiagnosticService.hdc,
      await tools.checkHarmonyEnvironment(),
    ),
    DiagnosticService.ios: () async => diagnosticForPlatformTool(
      DiagnosticService.ios,
      await tools.checkIosEnvironment(),
    ),
    DiagnosticService.mirror: _mirror,
    DiagnosticService.airplay: () => _airplay(ref),
    DiagnosticService.dlna: _dlna,
    DiagnosticService.transfer: () =>
        _transfer(ref.read(diagnosticShareCoreEnabledProvider)),
    DiagnosticService.mcp: () => _mcp(ref),
    DiagnosticService.virtualCamera: _virtualCamera,
    DiagnosticService.lanShare: sessions.lanShare,
    DiagnosticService.notifications: sessions.notifications,
    DiagnosticService.deviceSessions: sessions.deviceSessions,
  };
}

/// 尊重工具环境的显式状态，不将失败、未知或检查中伪装成依赖缺失。
ServiceDiagnostic diagnosticForPlatformTool(
  DiagnosticService id,
  PlatformEnvironmentInfo tool,
) {
  final status = switch (tool.status) {
    PlatformToolStatus.ready => ServiceDiagnosticStatus.ready,
    PlatformToolStatus.missing => ServiceDiagnosticStatus.missing,
    PlatformToolStatus.failed => ServiceDiagnosticStatus.error,
    PlatformToolStatus.checking ||
    PlatformToolStatus.downloading ||
    PlatformToolStatus.extracting => ServiceDiagnosticStatus.checking,
    PlatformToolStatus.unknown => ServiceDiagnosticStatus.unknown,
  };
  return ServiceDiagnostic(
    service: id,
    status: status,
    reasonKey: switch (status) {
      ServiceDiagnosticStatus.ready => 'diagnosticsToolReady',
      ServiceDiagnosticStatus.missing => 'diagnosticsToolMissing',
      ServiceDiagnosticStatus.checking => 'diagnosticsToolBusy',
      ServiceDiagnosticStatus.unknown => 'diagnosticsNoStatus',
      _ => 'diagnosticsFailedReason',
    },
    adviceKey: switch (status) {
      ServiceDiagnosticStatus.ready => 'diagnosticsReadyAdvice',
      ServiceDiagnosticStatus.unknown ||
      ServiceDiagnosticStatus.checking => 'diagnosticsUnknownAdvice',
      _ => 'diagnosticsToolAdvice',
    },
    details: [
      if (tool.executablePath.isNotEmpty)
        DiagnosticDetail('diagnosticsPath', tool.executablePath),
      if (tool.version.isNotEmpty)
        DiagnosticDetail('diagnosticsVersion', tool.version),
      if (tool.errorMessage.isNotEmpty)
        diagnosticErrorDetail(tool.errorMessage),
    ],
  );
}

/// 技术错误走日志脱敏，避免把服务凭据带进可复制的检查结果。
DiagnosticDetail diagnosticErrorDetail(Object error) => DiagnosticDetail(
  'diagnosticsTechnicalError',
  AppLogRecorder.sanitize(error.toString()),
);

ServiceDiagnostic diagnosticResult(
  DiagnosticService service,
  ServiceDiagnosticStatus status, {
  String? reason,
  String? advice,
  List<DiagnosticDetail> details = const [],
}) => ServiceDiagnostic(
  service: service,
  status: status,
  reasonKey:
      reason ??
      switch (status) {
        ServiceDiagnosticStatus.running => 'diagnosticsRunningReason',
        ServiceDiagnosticStatus.ready => 'diagnosticsReadyReason',
        ServiceDiagnosticStatus.disabled => 'diagnosticsDisabledReason',
        ServiceDiagnosticStatus.unsupported => 'diagnosticsUnsupportedReason',
        ServiceDiagnosticStatus.missing => 'diagnosticsComponentMissing',
        ServiceDiagnosticStatus.permissionRequired =>
          'diagnosticsPermissionReason',
        ServiceDiagnosticStatus.unknown => 'diagnosticsNoStatus',
        _ => 'diagnosticsFailedReason',
      },
  adviceKey:
      advice ??
      switch (status) {
        ServiceDiagnosticStatus.disabled => 'diagnosticsDisabledAdvice',
        ServiceDiagnosticStatus.unsupported => 'diagnosticsUnsupportedAdvice',
        ServiceDiagnosticStatus.missing => 'diagnosticsComponentAdvice',
        ServiceDiagnosticStatus.permissionRequired =>
          'diagnosticsPermissionAdvice',
        ServiceDiagnosticStatus.error => 'diagnosticsErrorAdvice',
        ServiceDiagnosticStatus.unknown => 'diagnosticsUnknownAdvice',
        _ => 'diagnosticsReadyAdvice',
      },
  details: details,
);

Future<ServiceDiagnostic> _mirror() async {
  const id = DiagnosticService.mirror;
  if (Platform.isMacOS) {
    try {
      final library = RustDeviceBridge.instance.library;
      if (!library.providesSymbol('anydeck_start_mirror') ||
          !library.providesSymbol('anydeck_start')) {
        return diagnosticResult(id, ServiceDiagnosticStatus.missing);
      }
      final server = await rootBundle.load('assets/scrcpy/scrcpy-server.jar');
      if (server.lengthInBytes == 0) {
        return diagnosticResult(id, ServiceDiagnosticStatus.missing);
      }
      return diagnosticResult(
        id,
        ServiceDiagnosticStatus.ready,
        reason: 'diagnosticsMirrorReady',
        advice: 'diagnosticsMirrorAdvice',
      );
    } catch (error) {
      return diagnosticResult(
        id,
        ServiceDiagnosticStatus.missing,
        details: [diagnosticErrorDetail(error)],
      );
    }
  }
  final path = resolveToolPath('scrcpy');
  final result = await runBoundedProcess(path, ['--version']);
  return diagnosticResult(
    id,
    result.exitCode == 0
        ? ServiceDiagnosticStatus.ready
        : ServiceDiagnosticStatus.error,
    reason: result.exitCode == 0 ? 'diagnosticsMirrorCliReady' : null,
    advice: 'diagnosticsMirrorAdvice',
    details: [
      DiagnosticDetail('diagnosticsPath', path),
      DiagnosticDetail('diagnosticsVersion', '${result.stdout}'.trim()),
      if (result.exitCode != 0) diagnosticErrorDetail(result.stderr),
    ],
  );
}

Future<ServiceDiagnostic> _airplay(Ref ref) async {
  const id = DiagnosticService.airplay;
  if (!Platform.isMacOS) {
    return diagnosticResult(id, ServiceDiagnosticStatus.unsupported);
  }
  final service = AirPlayServerService.instance;
  if (!service.isSupported) {
    return diagnosticResult(id, ServiceDiagnosticStatus.missing);
  }
  final session = ref.read(airplaySessionProvider.exists)
      ? ref.read(airplaySessionProvider)
      : null;
  if (session == null) {
    return diagnosticResult(id, ServiceDiagnosticStatus.disabled);
  }
  final errors = [
    for (final item in session.allSessions)
      if (service.getStatus(item.id) == AirPlayServerStatus.stopped)
        diagnosticErrorDetail(service.getLastError(item.id) ?? 'stopped'),
  ];
  if (errors.isNotEmpty) {
    return diagnosticResult(id, ServiceDiagnosticStatus.error, details: errors);
  }
  return _listening(
    id,
    session.rtspPort,
    details: [DiagnosticDetail('diagnosticsReceiverName', session.serverName)],
    reason: session.isPublished ? null : 'diagnosticsAirplayPublishing',
    successStatus: session.isPublished
        ? ServiceDiagnosticStatus.running
        : ServiceDiagnosticStatus.unknown,
  );
}

Future<ServiceDiagnostic> _dlna() async {
  const id = DiagnosticService.dlna;
  if (!Platform.isMacOS) {
    return diagnosticResult(id, ServiceDiagnosticStatus.unsupported);
  }
  final service = DlnaRendererService.instance;
  if (service.error != null || service.playbackError != null) {
    return diagnosticResult(
      id,
      ServiceDiagnosticStatus.error,
      details: [diagnosticErrorDetail(service.error ?? service.playbackError!)],
    );
  }
  if (!service.isRunning) {
    return diagnosticResult(id, ServiceDiagnosticStatus.disabled);
  }
  return _listening(id, service.httpPort);
}

Future<ServiceDiagnostic> _mcp(Ref ref) async {
  const id = DiagnosticService.mcp;
  if (!ref.read(mcpServerProvider.exists)) {
    return diagnosticResult(id, ServiceDiagnosticStatus.disabled);
  }
  final state = ref.read(mcpServerProvider);
  if (state.lastError != null) {
    return diagnosticResult(
      id,
      ServiceDiagnosticStatus.error,
      details: [diagnosticErrorDetail(state.lastError!)],
    );
  }
  if (!state.isRunning) {
    return diagnosticResult(id, ServiceDiagnosticStatus.disabled);
  }
  final host = switch (state.config.host) {
    '0.0.0.0' => '127.0.0.1',
    '::' => '::1',
    final value => value,
  };
  return _listening(id, state.config.port, host: host);
}

/// 仅对已运行服务做本机连接，不绑定端口，也不把他人占用误报为本服务正常。
Future<ServiceDiagnostic> _listening(
  DiagnosticService id,
  int port, {
  String host = '127.0.0.1',
  String? reason,
  ServiceDiagnosticStatus successStatus = ServiceDiagnosticStatus.running,
  List<DiagnosticDetail> details = const [],
}) async {
  final fields = [
    DiagnosticDetail('diagnosticsEndpoint', '$host:$port'),
    ...details,
  ];
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
    return diagnosticResult(
      id,
      successStatus,
      reason: reason ?? 'diagnosticsListeningReason',
      details: fields,
    );
  } catch (error) {
    return diagnosticResult(
      id,
      ServiceDiagnosticStatus.error,
      reason: 'diagnosticsPortFailed',
      details: [...fields, diagnosticErrorDetail(error)],
    );
  }
}

Future<ServiceDiagnostic> _transfer(bool included) async {
  const id = DiagnosticService.transfer;
  if (!included) {
    return diagnosticResult(
      id,
      ServiceDiagnosticStatus.unsupported,
      reason: 'diagnosticsNotBundled',
    );
  }
  if (!Platform.isMacOS) {
    return diagnosticResult(id, ServiceDiagnosticStatus.unsupported);
  }
  final service = HarmonyShareService.instance;
  if (service.error != null) {
    return diagnosticResult(
      id,
      ServiceDiagnosticStatus.error,
      details: [diagnosticErrorDetail(service.error!)],
    );
  }
  // hello 仅校验制品握手，既有实现在finally回收子进程，不进入发现/收发模式。
  final capabilities = await const ShareCoreClient().probe();
  if (!capabilities.discovery || !capabilities.send || !capabilities.receive) {
    return diagnosticResult(id, ServiceDiagnosticStatus.missing);
  }
  return diagnosticResult(
    id,
    service.enabled && (service.scanning || service.busy || service.receiving)
        ? ServiceDiagnosticStatus.running
        : service.startingDiscovery
        ? ServiceDiagnosticStatus.unknown
        : ServiceDiagnosticStatus.disabled,
    reason: service.startingDiscovery ? 'diagnosticsPreparingReason' : null,
    details: [DiagnosticDetail('diagnosticsVersion', capabilities.coreVersion)],
  );
}

Future<ServiceDiagnostic> _virtualCamera() async {
  const id = DiagnosticService.virtualCamera;
  if (!Platform.isMacOS) {
    return diagnosticResult(id, ServiceDiagnosticStatus.unsupported);
  }
  final map = await const MethodChannel('anydeck/virtual_camera')
      .invokeMapMethod<Object?, Object?>('status')
      .timeout(const Duration(seconds: 5));
  if (map == null || map['supported'] is! bool) {
    return diagnosticResult(
      id,
      ServiceDiagnosticStatus.unknown,
      reason: 'diagnosticsNoStatus',
    );
  }
  final state = VirtualCameraState.fromMap(map);
  final status = switch (state) {
    VirtualCameraState(supported: false) => ServiceDiagnosticStatus.unsupported,
    VirtualCameraState(error: final error?) when error.isNotEmpty =>
      ServiceDiagnosticStatus.error,
    VirtualCameraState(activation: 'needsApproval' || 'needsReboot') =>
      ServiceDiagnosticStatus.permissionRequired,
    VirtualCameraState(installed: false) => ServiceDiagnosticStatus.disabled,
    VirtualCameraState(streaming: true) => ServiceDiagnosticStatus.running,
    VirtualCameraState(activation: 'ready') => ServiceDiagnosticStatus.ready,
    _ => ServiceDiagnosticStatus.unknown,
  };
  return diagnosticResult(
    id,
    status,
    reason: state.messageKey,
    advice: 'diagnosticsCameraAdvice',
  );
}
