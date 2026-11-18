import 'dart:convert';

import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/harmony_share/controller/harmony_share_providers.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/src/internals.dart' show Override;

/// 固定有效 PNG，避免测试 setUp 在 FakeAsync 边界等待引擎绘制与编码。
Uint8List screenshotLayoutPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// 侧栏仅验证导航，隔离设置原生初始化、MCP 凭据和设备概览探针。
List<Override> screenshotRailServiceOverrides(String deviceId) => [
  appSettingsProvider.overrideWith(_Settings.new),
  mcpServerProvider.overrideWith(_IdleMcp.new),
  deviceOverviewProvider(deviceId).overrideWith(
    (ref) => Stream.value(DeviceOverview.fromJson({'serial': deviceId})),
  ),
  harmonyShareServiceProvider.overrideWith((ref) {
    final share = _IdleShare();
    ref.onDispose(share.dispose);
    return share;
  }),
];

class _Settings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

class _IdleMcp extends McpServerNotifier {
  @override
  McpServerState build() => const McpServerState(
    isRunning: false,
    statusText: '',
    config: McpServerConfig(),
    registeredTools: [],
  );
}

class _IdleShare extends ChangeNotifier implements HarmonyShareService {
  @override
  bool get enabled => false;
  @override
  bool get scanning => false;
  @override
  bool get busy => false;
  @override
  String? get error => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
