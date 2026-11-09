import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/device_share/hosted_device_share.dart';
import 'package:any_deck/core/device_share/joined_device_share.dart';
import 'package:any_deck/core/device_share/share_socket_reader.dart';
import 'package:any_deck/core/device_share/share_tls_identity.dart';
import 'package:any_deck/core/process/tool_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_share_fixture.dart';
import 'support/shared_sync_fixture.dart';

/// 独立端口且 --one-device 指向不存在的 serial，不接管用户的 ADB Server 或 USB。
class _IsolatedAdb extends AdbService {
  _IsolatedAdb(String executable, this.port) : super(executable: executable);
  final int port;
  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) => super.run(['-P', '$port', ...args], timeout: timeout);
}

Uint8List _shellFrame(int channel, List<int> data) {
  final bytes = Uint8List(data.length + 5)..[0] = channel;
  ByteData.sublistView(bytes).setUint32(1, data.length, Endian.little);
  bytes.setRange(5, bytes.length, data);
  return bytes;
}

void main() {
  late Process process;
  late _IsolatedAdb localAdb;
  late ShareTlsIdentity identity;
  late ShareAdbFixture source;
  late HostedDeviceShare host;
  JoinedDeviceShare? joined;
  late Directory directory;
  final sync = SharedSyncFixture();
  final binary = resolveToolPath('adb');
  if (!File(binary).existsSync()) {
    test('真实 ADB 集成需要本机 platform-tools', () {}, skip: 'ADB binary unavailable');
    return;
  }

  setUpAll(() async {
    identity = await ShareTlsIdentity.generate();
    directory = await Directory.systemTemp.createTemp('anydeck-share-adb-');
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    process = await Process.start(
      binary,
      [
        '-L',
        'tcp:$port',
        '--one-device',
        'ANYDECK_SHARE_TEST_NO_USB',
        'server',
        'nodaemon',
      ],
      environment: {'ADB_MDNS_AUTO_CONNECT': ''},
    );
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    localAdb = _IsolatedAdb(binary, port);
    for (var attempt = 0; ; attempt++) {
      try {
        final ready = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 100),
        );
        ready.destroy();
        break;
      } catch (_) {
        if (attempt >= 50) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  tearDownAll(() async {
    await localAdb.run(['kill-server']);
    process.kill();
    await process.exitCode;
    await directory.delete(recursive: true);
  });

  setUp(() async {
    source = ShareAdbFixture()..features = 'shell_v2';
    source.onService = (service, socket, reader) async {
      if (service == 'sync:') {
        await sync.handle(socket, reader);
      } else if (service.startsWith('shell,v2')) {
        socket.add(_shellFrame(1, utf8.encode('AnyDeck shared shell\n')));
        socket.add(_shellFrame(3, [0]));
      } else {
        socket.add([0, 255, 10, 13, 128, 42]);
      }
    };
    await source.start();
    host = await HostedDeviceShare.start(
      deviceId: 'fixture-usb',
      backend: source.backend,
      host: '127.0.0.1',
      identity: identity,
      onChanged: () {},
      bindAddress: InternetAddress.loopbackIPv4,
    );
    joined = await JoinedDeviceShare.connect(host.invitation, localAdb, () {});
  });

  tearDown(() async {
    await joined?.close();
    joined = null;
    await host.close();
    await source.close();
  });

  test('真实 adb 识别共享设备，Shell v2 退出码与 exec-out 二进制正确', () async {
    final devices = await localAdb.listDevices();
    expect(
      devices.where((device) => device.isShared).single.id,
      joined!.deviceId,
    );
    final result = await localAdb.run([
      '-s',
      joined!.deviceId,
      'shell',
      'echo',
      'test',
    ]);
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, 'AnyDeck shared shell\n');
    final binary = await Process.run(localAdb.executable, [
      '-P',
      '${localAdb.port}',
      '-s',
      joined!.deviceId,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null);
    expect(binary.exitCode, 0, reason: '${binary.stderr}');
    expect(binary.stdout, [0, 255, 10, 13, 128, 42]);
  });

  test('真实 adb push/pull 经 TLS 与 Transport 往返，内容逐字节一致', () async {
    final content = Uint8List.fromList(List.generate(180000, (i) => i % 251));
    final input = File('${directory.path}/input.bin');
    final output = File('${directory.path}/output.bin');
    await input.writeAsBytes(content);
    final pushed = await localAdb.run([
      '-s',
      joined!.deviceId,
      'push',
      '-Z',
      input.path,
      '/data/local/tmp/anydeck-share-test.bin',
    ]);
    expect(pushed.exitCode, 0, reason: pushed.message);
    expect(sync.files['/data/local/tmp/anydeck-share-test.bin'], content);
    final pulled = await localAdb.run([
      '-s',
      joined!.deviceId,
      'pull',
      '-Z',
      '/data/local/tmp/anydeck-share-test.bin',
      output.path,
    ]);
    expect(pulled.exitCode, 0, reason: pulled.message);
    expect(await output.readAsBytes(), content);
  });

  test('真实 adb forward 在接收端建立端口，投屏 Socket 可读取二进制', () async {
    final forwarded = await localAdb.run([
      '-s',
      joined!.deviceId,
      'forward',
      'tcp:0',
      'localabstract:scrcpy_share_test',
    ]);
    expect(forwarded.exitCode, 0, reason: forwarded.message);
    final socket = await Socket.connect(
      '127.0.0.1',
      int.parse(forwarded.stdout.trim()),
    );
    final reader = ShareSocketReader(socket);
    expect(await reader.read(6), [0, 255, 10, 13, 128, 42]);
    socket.destroy();
    await reader.cancel();
  });

  test('并发设备信息查询与大文件推送共用 Transport 时保持所有服务可用', () async {
    final ready = Completer<void>();
    var queries = 0;
    source.onService = (service, socket, reader) async {
      if (service == 'sync:') {
        await sync.handle(socket, reader);
        return;
      }
      if (service.startsWith('shell,v2')) {
        if (++queries == 4) ready.complete();
        await ready.future;
        socket.add(
          _shellFrame(1, utf8.encode('AnyDeck concurrent metadata\n' * 4096)),
        );
        socket.add(_shellFrame(3, [0]));
      }
    };
    final content = Uint8List.fromList(List.generate(900000, (i) => i % 239));
    final input = File('${directory.path}/concurrent.bin');
    await input.writeAsBytes(content);
    final results = await Future.wait([
      for (var i = 0; i < 4; i++)
        localAdb.shellArgs(joined!.deviceId, ['getprop', 'test.$i']),
      localAdb.run([
        '-s',
        joined!.deviceId,
        'push',
        '-Z',
        input.path,
        '/data/local/tmp/anydeck-concurrent.bin',
      ]),
    ]);
    expect(
      results.map((result) => result.exitCode),
      everyElement(0),
      reason: results.map((result) => result.message).join('\n'),
    );
    for (final result in results.take(4)) {
      expect(result.stdout, 'AnyDeck concurrent metadata\n' * 4096);
    }
    expect(sync.files['/data/local/tmp/anydeck-concurrent.bin'], content);
    expect(joined!.closed, isFalse);
  });

  test('真实 adb 流式安装保留 ABB 的 NUL 参数与 APK 字节', () async {
    // 重建连接以重新协商 ABB 能力，不依赖手机或有效 APK 签名。
    await joined!.close();
    source.features = 'shell_v2,cmd,abb,abb_exec';
    final content = Uint8List.fromList(List.generate(12000, (i) => i % 239));
    final apk = File('${directory.path}/shared-test.apk');
    await apk.writeAsBytes(content);
    Uint8List? received;
    String? request;
    source.onService = (service, socket, reader) async {
      request = service;
      if (service.startsWith('abb_exec:')) {
        received = await reader.read(content.length);
        socket.write('Success\n');
      } else if (service.startsWith('shell,v2')) {
        socket.add(_shellFrame(1, utf8.encode('34\n')));
        socket.add(_shellFrame(3, [0]));
      }
    };
    joined = await JoinedDeviceShare.connect(host.invitation, localAdb, () {});
    final installed = await localAdb.run([
      '-s',
      joined!.deviceId,
      'install',
      '--streaming',
      apk.path,
    ]);
    expect(installed.exitCode, 0, reason: installed.message);
    expect(request, startsWith('abb_exec:'));
    expect(request, contains('\u0000'));
    expect(received, content);
  });

  test('真实 adb reverse 回连接收端，list 和 remove 不泄露宿主其他规则', () async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(listener.close);
    final accepted = listener.first;
    source.reversePorts['tcp:1111'] = 2222;
    final result = await localAdb.run([
      '-s',
      joined!.deviceId,
      'reverse',
      'tcp:43001',
      'tcp:${listener.port}',
    ]);
    expect(result.exitCode, 0, reason: result.message);
    final callback = await Socket.connect(
      '127.0.0.1',
      source.reversePorts['tcp:43001']!,
    );
    final destination = await accepted.timeout(const Duration(seconds: 5));
    final destinationReader = ShareSocketReader(destination);
    callback.add([21, 22, 23]);
    await callback.flush();
    expect(await destinationReader.read(3), [21, 22, 23]);
    final list = await localAdb.run([
      '-s',
      joined!.deviceId,
      'reverse',
      '--list',
    ]);
    expect(list.exitCode, 0, reason: list.message);
    expect(list.stdout, contains('tcp:43001 tcp:${listener.port}'));
    expect(list.stdout, isNot(contains('1111')));
    final removed = await localAdb.run([
      '-s',
      joined!.deviceId,
      'reverse',
      '--remove-all',
    ]);
    expect(removed.exitCode, 0, reason: removed.message);
    expect(source.reversePorts, {'tcp:1111': 2222});
    callback.destroy();
    destination.destroy();
    await destinationReader.cancel();
    await listener.close();
  });

  test('分享方撤销后接收端立即离线，其他本机 ADB Server 不受影响', () async {
    await host.close();
    for (var attempt = 0; !joined!.closed && attempt < 100; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(joined!.closed, isTrue);
    await joined!.close();
    final devices = await localAdb.listDevices();
    expect(devices.where((device) => device.id == joined!.deviceId), isEmpty);
    final version = await localAdb.run(['server-status']);
    expect(version.exitCode, 0);
  });
}
