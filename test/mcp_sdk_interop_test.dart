import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/mcp/mcp_server.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/mcp/models/mcp_tool_definition.dart';
import 'package:any_deck/core/mcp/registry/mcp_tool_registry.dart';

/// 可选的官方 SDK 互操作测试；SDK 通过环境变量提供，不修改产品依赖。
void main() {
  test(
    '官方 SDK：三个平台的两代 HTTP 协议及兼容 SSE',
    () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final registry = McpToolRegistry()..resolvePlatform = (id) async => id;
      for (final p in ['android', 'harmony', 'ios']) {
        registry.register(
          McpToolDefinition(
            name: '${p}_probe',
            description: 'SDK 验证读取',
            platforms: {p},
            inputSchema: const {
              'type': 'object',
              'properties': {
                'deviceId': {'type': 'string'},
              },
              'required': ['deviceId'],
            },
            handler: (_) async => {'platform': p},
          ),
        );
      }
      final server = McpServer(
        registry: registry,
        config: McpServerConfig(
          port: port,
          enableLegacy: true,
          platformTokens: const {
            'android': 'android-test',
            'harmony': 'harmony-test',
            'ios': 'ios-test',
          },
        ),
      );
      await server.startSse();
      try {
        final process = await Process.start('node', [
          'test/fixtures/mcp/sdk_probe.mjs',
          '$port',
        ]);
        final output = process.stdout.transform(utf8.decoder).join();
        final errors = process.stderr.transform(utf8.decoder).join();
        int code;
        try {
          code = await process.exitCode.timeout(const Duration(seconds: 20));
        } catch (_) {
          process.kill(ProcessSignal.sigkill);
          code = -1;
        }
        final stdout = await output;
        final stderr = await errors;
        expect(code, 0, reason: '$stdout\n$stderr');
        expect(stdout, contains('PASS:'));
      } finally {
        await server.stop();
      }
    },
    skip: Platform.environment['ANYDECK_MCP_SDK'] == null
        ? '设置 ANYDECK_MCP_SDK 为官方 SDK ESM 路径后运行'
        : false,
  );
}
