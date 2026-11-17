import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../../core/device_share/device_share_provider.dart';
import '../../../core/diagnostics/service_diagnostic.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../apps/controller/camera_preview_controller.dart';
import '../../apps/controller/device_auxiliary_controller.dart';
import '../../control/controller/audio_forward_controller.dart';
import 'service_diagnostic_checks.dart';

/// 仅读取已存在会话；检查页面不得成为设备采集、重连或后台轮询的新拥有者。
class ServiceSessionChecks {
  ServiceSessionChecks(this.ref);
  final Ref ref;

  Future<ServiceDiagnostic> lanShare() async {
    const id = DiagnosticService.lanShare;
    if (!ref.read(deviceShareServiceProvider.exists)) {
      return diagnosticResult(id, ServiceDiagnosticStatus.disabled);
    }
    final service = ref.read(deviceShareServiceProvider);
    if (service.initializationError != null) {
      return diagnosticResult(
        id,
        ServiceDiagnosticStatus.error,
        details: [diagnosticErrorDetail(service.initializationError!)],
      );
    }
    if (!service.ready) {
      return diagnosticResult(
        id,
        ServiceDiagnosticStatus.unknown,
        reason: 'diagnosticsPreparingReason',
      );
    }
    final count = service.hosts.length + service.joins.length;
    return diagnosticResult(
      id,
      count > 0
          ? ServiceDiagnosticStatus.running
          : ServiceDiagnosticStatus.disabled,
      reason: count > 0 ? 'diagnosticsLanRunning' : null,
      details: [
        DiagnosticDetail('diagnosticsSessionCount', '$count'),
        for (final host in service.hosts)
          DiagnosticDetail(
            'diagnosticsEndpoint',
            '${host.invitation.host}:${host.invitation.port}',
          ),
      ],
    );
  }

  Future<ServiceDiagnostic> notifications() async {
    const id = DiagnosticService.notifications;
    if (!Platform.isMacOS) {
      return diagnosticResult(id, ServiceDiagnosticStatus.unsupported);
    }
    final settings = ref.read(appSettingsProvider);
    final service = ref.read(notificationForwardingServiceProvider.exists)
        ? ref.read(notificationForwardingServiceProvider)
        : null;
    final sessions = service?.activeSessionDeviceIds ?? const <String>[];
    final errors = [
      for (final device in sessions)
        if (service!.getSessionError(device) case final error?)
          diagnosticErrorDetail(error),
    ];
    if (errors.isNotEmpty) {
      return diagnosticResult(
        id,
        ServiceDiagnosticStatus.error,
        reason: 'diagnosticsNotificationFailed',
        details: errors,
      );
    }
    if (!settings.deviceConnectNotification &&
        !settings.harmonyShareNotifications &&
        sessions.isEmpty) {
      return diagnosticResult(id, ServiceDiagnosticStatus.disabled);
    }
    final permission = await const MethodChannel('any_deck/notifications')
        .invokeMethod<String>('getAuthorizationStatus')
        .timeout(const Duration(seconds: 5));
    return diagnosticResult(
      id,
      switch (permission) {
        'authorized' || 'provisional' =>
          sessions.isEmpty
              ? ServiceDiagnosticStatus.ready
              : ServiceDiagnosticStatus.running,
        'denied' ||
        'notDetermined' => ServiceDiagnosticStatus.permissionRequired,
        _ => ServiceDiagnosticStatus.unknown,
      },
      reason: switch (permission) {
        'authorized' || 'provisional' => 'diagnosticsNotificationsReady',
        'denied' || 'notDetermined' => 'diagnosticsNotificationsPermission',
        _ => 'diagnosticsNoStatus',
      },
      advice: 'diagnosticsNotificationsAdvice',
      details: [
        DiagnosticDetail('diagnosticsSessionCount', '${sessions.length}'),
      ],
    );
  }

  Future<ServiceDiagnostic> deviceSessions() async {
    const id = DiagnosticService.deviceSessions;
    if (!Platform.isMacOS) {
      return diagnosticResult(id, ServiceDiagnosticStatus.unsupported);
    }
    final devices = ref.read(deviceRegistryProvider.exists)
        ? ref.read(deviceRegistryProvider)
        : const <RegisteredDevice>[];
    var active = 0;
    var preparing = false;
    final errors = <DiagnosticDetail>[];
    for (final device in devices) {
      final camera = cameraPreviewProvider(device.id);
      if (ref.read(camera.exists)) {
        final state = ref.read(camera);
        if (state.isStreaming) active++;
        preparing = preparing || state.busy;
        if (state.messageKey case final key?
            when key.endsWith('Failed') || key == 'cameraDisconnected') {
          errors.add(DiagnosticDetail('diagnosticsMessageKey', key));
        }
      }
      final audio = audioForwardControllerProvider(device.id);
      if (ref.read(audio.exists)) {
        final state = ref.read(audio);
        if (state.isActive) active++;
        preparing = preparing || state.isStarting || state.isStopping;
        if (state.errorMessage case final error?) {
          errors.add(diagnosticErrorDetail(error));
        }
      }
      for (final microphone in [false, true]) {
        final auxiliary = deviceAuxiliaryProvider((
          deviceId: device.id,
          microphone: microphone,
        ));
        if (!ref.read(auxiliary.exists)) continue;
        final state = ref.read(auxiliary);
        if (state.active) active++;
        preparing = preparing || state.busy;
        if (state.failed) {
          errors.add(
            DiagnosticDetail('diagnosticsMessageKey', state.messageKey),
          );
        }
      }
    }
    return diagnosticResult(
      id,
      errors.isNotEmpty
          ? ServiceDiagnosticStatus.error
          : preparing
          ? ServiceDiagnosticStatus.unknown
          : active > 0
          ? ServiceDiagnosticStatus.running
          : ServiceDiagnosticStatus.disabled,
      reason: 'diagnosticsSessionsScope',
      advice: 'diagnosticsSessionsAdvice',
      details: [
        DiagnosticDetail('diagnosticsSessionCount', '$active'),
        ...errors,
      ],
    );
  }
}
