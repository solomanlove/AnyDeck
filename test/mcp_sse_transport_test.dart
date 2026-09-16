import 'dart:io';

import 'package:any_deck/core/mcp/transport/mcp_sse_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('停止有两个 SSE 客户端的服务时正常清理连接', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();

    final transport = McpSseTransport(port: port);
    final client = HttpClient();
    try {
      await transport.start(onRequest: (_) async => null);

      for (var i = 0; i < 2; i++) {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/sse'),
        );
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        response.listen((_) {});
      }

      expect(transport.clientCount, 2);
      await transport.stop();
      expect(transport.clientCount, 0);
      expect(transport.isRunning, isFalse);
    } finally {
      await transport.stop();
      client.close(force: true);
    }
  });
}
