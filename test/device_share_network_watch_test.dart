import 'dart:async';

import 'package:any_deck/core/device_share/device_share_network_watch.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/network/host_network_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Network extends HostNetworkService {
  int reads = 0, active = 0, maximum = 0;
  final started = Completer<void>();
  Completer<void>? gate;
  @override
  Future<HostNetworkInfo> read() =>
      throw StateError('Regular read is not for automatic sharing');
  @override
  Future<HostNetworkInfo> readForSharing() async {
    reads++;
    active++;
    if (active > maximum) maximum = active;
    if (!started.isCompleted) started.complete();
    await gate?.future;
    active--;
    return const HostNetworkInfo(ssid: 'Office', verifiedWifiSsid: 'Office');
  }
}

/// 以原生事件桩验证即时读取、防抖、背压和监听生命周期。
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('any_deck/host_network/events');
  final calls = <String>[];
  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  test('订阅立即读取，连续系统事件合并后更新，取消时停止原生监听', () async {
    final service = _Network();
    final first = Completer<void>(), second = Completer<void>();
    final subscription =
        DeviceShareNetworkWatch(
          service,
          interval: const Duration(hours: 1),
        ).watch().listen((network) {
          if (!first.isCompleted) {
            first.complete();
          } else if (!second.isCompleted) {
            second.complete();
          }
        });
    await first.future.timeout(const Duration(seconds: 2));
    expect(service.reads, 1);
    for (var i = 0; i < 5; i++) {
      binding.channelBuffers.push(
        channel.name,
        const StandardMethodCodec().encodeSuccessEnvelope(null),
        (_) {},
      );
    }
    await second.future.timeout(const Duration(seconds: 2));
    expect(service.reads, 2);
    await subscription.cancel();
    expect(calls, ['listen', 'cancel']);
  });

  test('慢网络读取不会并发堆积，取消后不再触发定时读取', () async {
    final service = _Network()..gate = Completer<void>();
    final subscription = DeviceShareNetworkWatch(
      service,
      interval: const Duration(milliseconds: 10),
    ).watch().listen((_) {});
    await service.started.future;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(service.maximum, 1);
    expect(service.reads, 1);
    await subscription.cancel();
    service.gate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(service.reads, 1);
  });

  test('同名展示 Wi-Fi 缺少系统关联确认时，自动规则拿不到可信 SSID', () {
    final network = HostNetworkInfo.resolve(
      {
        'wifiInterfaces': [
          {'name': 'en0', 'ssid': 'Office', 'connected': true},
        ],
      },
      const [HostNetworkAddress('en0', '192.0.2.10')],
    );
    expect(network.ssid, 'Office');
    expect(network.verifiedWifiSsid, isNull);
  });

  test('系统确认的 SSID 与 Wi-Fi 网卡地址一起保留给自动准备', () {
    final network = HostNetworkInfo.resolve(
      {
        'wifiInterfaces': [
          {
            'name': 'en0',
            'ssid': 'Office',
            'verifiedSsid': 'Office',
            'connected': true,
          },
        ],
      },
      const [HostNetworkAddress('en0', '192.0.2.10')],
    );
    expect(network.verifiedWifiSsid, 'Office');
    expect(network.isWifiAddress, isTrue);
    expect(network.address?.ipv4, '192.0.2.10');
  });
}
