import 'dart:io';

import 'package:any_deck/core/airplay/airplay_server_service.dart';
import 'package:any_deck/core/device_share/device_share_provider.dart';
import 'package:any_deck/core/diagnostics/service_diagnostic.dart';
import 'package:any_deck/core/environment/connection_environment_service.dart';
import 'package:any_deck/core/notifications/notification_providers.dart';
import 'package:any_deck/core/process/tool_path_resolver.dart';
import 'package:any_deck/features/diagnostics/controller/service_diagnostics_controller.dart';
import 'package:any_deck/features/diagnostics/controller/service_diagnostic_checks.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('创建诊断适配器和检查未启用项不会初始化常驻服务', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final checks = container.read(serviceDiagnosticChecksProvider);
    final mcp = await checks[DiagnosticService.mcp]!();
    final share = await checks[DiagnosticService.lanShare]!();
    expect(mcp.status, ServiceDiagnosticStatus.disabled);
    expect(share.status, ServiceDiagnosticStatus.disabled);
    expect(container.read(mcpServerProvider.exists), isFalse);
    expect(container.read(deviceShareServiceProvider.exists), isFalse);
    expect(container.read(airplaySessionProvider.exists), isFalse);
    expect(
      container.read(notificationForwardingServiceProvider.exists),
      isFalse,
    );
  });

  test('工具显式失败、未知和处理中分别映射，不统一误报为缺失', () {
    const expected = {
      PlatformToolStatus.ready: ServiceDiagnosticStatus.ready,
      PlatformToolStatus.missing: ServiceDiagnosticStatus.missing,
      PlatformToolStatus.failed: ServiceDiagnosticStatus.error,
      PlatformToolStatus.checking: ServiceDiagnosticStatus.checking,
      PlatformToolStatus.downloading: ServiceDiagnosticStatus.checking,
      PlatformToolStatus.extracting: ServiceDiagnosticStatus.checking,
      PlatformToolStatus.unknown: ServiceDiagnosticStatus.unknown,
    };
    for (final status in PlatformToolStatus.values) {
      final result = diagnosticForPlatformTool(
        DiagnosticService.adb,
        PlatformEnvironmentInfo(
          platform: TargetPlatformType.android,
          status: status,
          toolName: 'adb',
        ),
      );
      expect(result.status, expected[status]);
      expect(
        result.needsAttention,
        status == PlatformToolStatus.failed ||
            status == PlatformToolStatus.missing,
      );
    }
  });

  test('不含 Share Core 的构建不探测缺失依赖，不计入故障', () async {
    final container = ProviderContainer(
      overrides: [diagnosticShareCoreEnabledProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);
    final result = await container.read(
      serviceDiagnosticChecksProvider,
    )[DiagnosticService.transfer]!();
    expect(result.status, ServiceDiagnosticStatus.unsupported);
    expect(result.reasonKey, 'diagnosticsNotBundled');
    expect(result.needsAttention, isFalse);
    expect(result.details, isEmpty);
  });

  test('真实工具适配器共用路径配置和CLI输出，HDC兼容版本命令回退', () async {
    final directory = await Directory.systemTemp.createTemp('anydeck-tools-');
    final before = {...customToolPaths};
    addTearDown(() async {
      customToolPaths
        ..clear()
        ..addAll(before);
      await directory.delete(recursive: true);
    });
    Future<File> tool(String name, String body) async {
      final file = File('${directory.path}/$name');
      await file.writeAsString('#!/bin/sh\n$body\n');
      await Process.run('/bin/chmod', ['+x', file.path]);
      registerCustomToolPath(name, file.path);
      return file;
    }

    final adb = await tool(
      'adb',
      'printf "Android Debug Bridge version 1.0.41\\n"',
    );
    final hdc = await tool(
      'hdc',
      'if [ "\$1" = "-v" ]; then exit 1; fi; printf "HDC 3.1\\n"',
    );
    final ios = await tool('ios', 'printf \'{"version":"1.2.3"}\\n\'');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final checks = container.read(serviceDiagnosticChecksProvider);
    for (final (id, path, version) in [
      (DiagnosticService.adb, adb.path, 'Android Debug Bridge version 1.0.41'),
      (DiagnosticService.hdc, hdc.path, 'HDC 3.1'),
      (DiagnosticService.ios, ios.path, 'v1.2.3'),
    ]) {
      final result = await checks[id]!();
      expect(
        result.status,
        ServiceDiagnosticStatus.ready,
        reason:
            '${id.name}: ${result.details.map((item) => item.value).join('; ')}',
      );
      expect(result.reasonKey, 'diagnosticsToolReady');
      expect(
        result.details
            .singleWhere((d) => d.labelKey == 'diagnosticsPath')
            .value,
        path,
      );
      expect(
        result.details
            .singleWhere((d) => d.labelKey == 'diagnosticsVersion')
            .value,
        version,
      );
    }
  }, skip: Platform.isWindows);

  test('虚拟摄像头状态一次性读取，不触发安装、授权或采集', () async {
    const channel = MethodChannel('anydeck/virtual_camera');
    final methods = <String>[];
    var snapshot = <String, Object?>{
      'supported': true,
      'installed': true,
      'activation': 'needsApproval',
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return snapshot;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final check = container.read(
      serviceDiagnosticChecksProvider,
    )[DiagnosticService.virtualCamera]!;
    expect((await check()).status, ServiceDiagnosticStatus.permissionRequired);
    snapshot = {'supported': true, 'installed': false};
    expect((await check()).status, ServiceDiagnosticStatus.disabled);
    snapshot = {'supported': true, 'installed': true, 'activation': 'ready'};
    expect((await check()).status, ServiceDiagnosticStatus.ready);
    snapshot = {...snapshot, 'streaming': true};
    expect((await check()).status, ServiceDiagnosticStatus.running);
    snapshot = {...snapshot, 'error': 'cameraStartFailed'};
    expect((await check()).status, ServiceDiagnosticStatus.error);
    snapshot = {'supported': false, 'error': 'unsupported'};
    expect((await check()).status, ServiceDiagnosticStatus.unsupported);
    snapshot = {};
    expect((await check()).status, ServiceDiagnosticStatus.unknown);
    expect(methods, everyElement('status'));
    expect(methods.length, 7);
  }, skip: !Platform.isMacOS);
}
