import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/mcp/mcp_server.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/mcp/registry/mcp_tool_registry.dart';

/// 并发启动/停止后端口必须可独占绑定，避免遗留未持有的 HTTP listener。
void main() {
  Future<int> freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> assertReleased(int port) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
  }

  test('连续两次启动并发完成后，停止会释放唯一监听端口', () async {
    final port = await freePort();
    final server = McpServer(
      registry: McpToolRegistry(),
      config: McpServerConfig(port: port),
    );
    try {
      await Future.wait([server.startSse(), server.startSse()]);
      expect(server.isStarted, true);
      await server.stop();
      expect(server.isStarted, false);
      await assertReleased(port);
    } finally {
      await server.stop();
    }
  });

  test('启动尚未完成时停止，返回后不再残留运行中的服务', () async {
    final port = await freePort();
    final server = McpServer(
      registry: McpToolRegistry(),
      config: McpServerConfig(port: port),
    );
    try {
      final start = server.startSse();
      final stop = server.stop();
      await Future.wait([start, stop]);
      expect(server.isStarted, false);
      await assertReleased(port);
    } finally {
      await server.stop();
    }
  });
}
