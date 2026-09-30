import 'dart:async';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';

/// 用状态化 transport 模拟重启和认证，不启动任何真实 ADB 进程。
class WirelessAdbFake extends AdbService {
  WirelessAdbFake() : super(executable: 'unused-adb');
  final calls = <List<String>>[];
  final identities = <String, String>{};
  final online = <String>{};
  final reachable = <String>{};
  final ports = <String, String>{};
  final ips = <String, String>{};
  String mdns = '';
  bool enableSucceeds = true;
  bool tcpStarts = true;
  bool restartDropsTls = true;
  Completer<void>? enableGate;
  void Function(String)? onEnable;

  void add(
    String id,
    String serial, {
    String ip = '192.168.1.8',
    bool connected = true,
  }) {
    identities[id] = serial;
    ips[id] = ip;
    reachable.add(id);
    if (connected) online.add(id);
  }

  AdbResult ok([String output = '']) =>
      AdbResult(exitCode: 0, stdout: output, stderr: '');
  AdbResult fail() =>
      const AdbResult(exitCode: 1, stdout: '', stderr: 'offline');

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    calls.add(List.of(args));
    if (args.first == 'mdns') return ok(mdns);
    if (args.first == 'pair') return ok('Successfully paired to ${args[1]}');
    if (args.first == 'connect') {
      if (reachable.contains(args[1])) {
        online.add(args[1]);
        return ok('connected to ${args[1]}');
      }
      // 部分 ADB 版本以 exitCode=0 输出连接错误，测试必须识别实际 offline。
      return ok('failed to connect to ${args[1]}');
    }
    if (args.first == 'disconnect') {
      online.remove(args[1]);
      return ok('disconnected');
    }
    final id = args[1];
    if (!online.contains(id)) return fail();
    final command = args.skip(2).join(' ');
    if (command == 'get-state') return ok('device');
    if (command == 'shell getprop ro.serialno' ||
        command == 'shell getprop ro.boot.serialno') {
      return ok(identities[id] ?? '');
    }
    if (command == 'shell getprop service.adb.tcp.port') {
      return ok(ports[id] ?? '');
    }
    if (command == 'shell ip -4 route') {
      final ip = ips[id];
      return ok(
        ip == null
            ? ''
            : '192.168.1.0/24 dev wlan0 proto kernel scope link src $ip',
      );
    }
    if (command == 'tcpip 5555') {
      await enableGate?.future;
      if (!enableSucceeds) return fail();
      ports[id] = '5555';
      if (tcpStarts && ips[id] != null) {
        final address = '${ips[id]}:5555';
        add(address, identities[id]!, ip: ips[id]!, connected: false);
      }
      if (restartDropsTls && id.contains(':') && !id.endsWith(':5555')) {
        online.remove(id);
      }
      onEnable?.call(id);
      return ok('restarting in TCP mode port: 5555');
    }
    return ok();
  }
}
