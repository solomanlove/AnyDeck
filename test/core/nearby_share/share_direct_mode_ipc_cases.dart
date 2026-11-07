part of 'share_batch_sessions_test.dart';

/// 复用内存进程覆盖默认 LAN 和显式直连 IPC；不启动 native helper。
void _directModeIpcCases() {
  for (final direct in <bool?>[null, false, true]) {
    test('批次接收 IPC ${direct ?? "默认"} 模式写入明确 direct_mode', () async {
      final root = await Directory.systemTemp.createTemp('share-direct-ipc-');
      final process = _Process();
      var probes = 0;
      var launches = 0;
      final client = ShareBatchClient(
        probe: () async => probes++,
        launch: () async {
          launches++;
          return process;
        },
      );
      ShareBatchReceiveSession? session;
      StreamSubscription<Map<String, dynamic>>? subscription;
      try {
        final output = Directory('${root.path}/received');
        session = direct == null
            ? await client.receive(
                local: InternetAddress.loopbackIPv4,
                broadcast: InternetAddress('127.255.255.255'),
                output: output,
              )
            : await client.receive(
                local: InternetAddress.loopbackIPv4,
                broadcast: InternetAddress('127.255.255.255'),
                output: output,
                directMode: direct,
              );
        final events = <Map<String, dynamic>>[];
        subscription = session.events.listen(events.add);
        final request = jsonDecode(utf8.decode(process.written).trim());
        expect(request, {
          'version': ShareBatchContract.version,
          'command': 'receive_batch_interactive',
          'local_name': 'AnyDeck',
          'local_ip': '127.0.0.1',
          'broadcast_ip': '127.255.255.255',
          'output_dir': output.path,
          'duration_seconds': 120,
          'direct_mode': direct ?? false,
        });
        expect(probes, 1);
        expect(launches, 1);
        process.emit({'event': 'discovery_ready'});
        await Future<void>.delayed(Duration.zero);
        expect(events.single['event'], 'discovery_ready');
      } finally {
        await session?.stop();
        await subscription?.cancel();
        await process.stdin.close();
        await root.delete(recursive: true);
      }
    });
  }
}
