import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/mcp/controller/mcp_audit_log_controller.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 所有平台均返回空设备清单，避免测试触发宿主机 CLI 或真实设备操作。
class _Adb extends AdbService {
  @override
  Future<List<DiscoveredDevice>> listDevices() async => [];
}

class _Hdc extends HdcService {
  @override
  Future<List<DiscoveredDevice>> listDevices() async => [];
}

class _Ios extends IosDeviceService {
  @override
  Future<List<DiscoveredDevice>> listDevices() async => [];
}

/// 使用真实 HTTP listener 验证后台请求到页面 Provider 的审计链路。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late ProviderContainer container;
  late int port;
  late HttpClient client;
  setUp(() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = socket.port;
    await socket.close();
    SharedPreferences.setMockInitialValues({
      'anydeck_mcp_config_v1': jsonEncode({
        'enableSse': false,
        'enableLegacy': true,
        'port': port,
      }),
    });
    container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(_Adb()),
        hdcServiceProvider.overrideWithValue(_Hdc()),
        iosDeviceServiceProvider.overrideWithValue(_Ios()),
      ],
    );
    addTearDown(container.dispose);
    final initialized = Completer<void>();
    final subscription = container.listen(mcpServerProvider, (_, state) {
      if (state.registeredTools.isNotEmpty && !initialized.isCompleted) {
        initialized.complete();
      }
    });
    addTearDown(subscription.close);
    await initialized.future.timeout(const Duration(seconds: 5));
    final controller = container.read(mcpServerProvider.notifier);
    await controller.startServer();
    addTearDown(controller.stopServer);
    expect(container.read(mcpServerProvider).isRunning, true);

    client = HttpClient();
    addTearDown(() => client.close(force: true));
  });

  Future<Map<String, dynamic>> call(
    String path,
    String method,
    Map<String, dynamic> params,
  ) async {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('accept', 'application/json, text/event-stream');
    request.headers.set('mcp-protocol-version', '2025-11-25');
    if (path.startsWith('/mcp/')) {
      final platform = path.split('/').last;
      final token = container
          .read(mcpServerProvider)
          .config
          .platformTokens[platform];
      request.headers.set('authorization', 'Bearer $token');
    }
    request.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        'params': params,
      }),
    );
    final response = await request.close();
    expect(response.statusCode, 200);
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  }

  for (final path in ['/mcp', '/mcp/android', '/mcp/harmony', '/mcp/ios']) {
    test('页面未订阅时 $path 成功调用可在首次读取审计时看到', () async {
      final json = await call(path, 'tools/call', {
        'name': 'list_devices',
        'arguments': {},
      });
      expect(json['result']['isError'], false);
      final logs = container.read(mcpAuditLogProvider);
      expect(logs, hasLength(1));
      expect(logs.single.toolName, 'list_devices');
      expect(logs.single.isSuccess, true);
      expect(logs.single.responseSummary!.itemCount, 0);
      if (path != '/mcp') {
        expect(logs.single.responseSummary!.protocolVersion, '2025-11-25');
      }
      expect(
        logs.single.arguments?['platform'],
        path == '/mcp' ? 'all' : path.split('/').last,
      );
      expect(container.read(mcpServerProvider).totalRequestsCount, 1);
    });
  }

  test('工具调用失败只记录一条失败审计', () async {
    final json = await call('/mcp', 'tools/call', {
      'name': 'get_device_detail',
      'arguments': {},
    });
    expect(json['result']['isError'], true);
    final logs = container.read(mcpAuditLogProvider);
    expect(logs, hasLength(1));
    expect(logs.single.toolName, 'get_device_detail');
    expect(logs.single.isSuccess, false);
    expect(logs.single.responseSummary!.isToolError, true);
    expect(container.read(mcpServerProvider).totalRequestsCount, 1);
  });

  test('工具列表请求也会进入审计日志和请求计数', () async {
    final json = await call('/mcp', 'tools/list', {});
    expect(json['result']['tools'], isNotEmpty);
    final entry = container.read(mcpAuditLogProvider).single;
    expect(entry.method, 'tools/list');
    expect(
      entry.responseSummary!.itemCount,
      (json['result']['tools'] as List).length,
    );
    expect(container.read(mcpServerProvider).totalRequestsCount, 1);
  });
}
