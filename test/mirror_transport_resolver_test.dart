import 'dart:async';

import 'package:any_deck/core/scrcpy/mirror_transport_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/mirror_transport_fakes.dart';

void main() {
  test('USB 断开立即查询新列表，只切换到同一硬件的在线 TCP 连接', () async {
    final adb = TransportAdb()
      ..devices = 'phone offline\nother device\n192.168.1.8:5555 device'
      ..serials.addAll({'other': 'other', '192.168.1.8:5555': 'phone'});
    final resolver = MirrorTransportResolver(adb, 'phone');
    addTearDown(resolver.dispose);
    expect(await resolver.resolve(excluded: {'phone'}), '192.168.1.8:5555');
    expect(adb.calls.first, ['devices', '-l']);
    expect(adb.calls.where((args) => args.contains('phone')), isEmpty);
    expect(
      adb.timeouts.every((timeout) => timeout <= const Duration(seconds: 3)),
      isTrue,
    );
  });

  test('TLS/mDNS 名称含空格时保留完整路由，过滤未授权和离线连接', () async {
    const tls = 'adb-phone-xyz (2)._adb-tls-connect._tcp';
    final adb = TransportAdb()
      ..devices =
          '192.168.1.8:5555 offline\nunauth unauthorized\n$tls device model:Fold'
      ..serials[tls] = 'phone';
    final resolver = MirrorTransportResolver(adb, 'phone');
    addTearDown(resolver.dispose);
    expect(await resolver.resolve(excluded: {'phone'}), tls);
    expect(adb.calls.last[1], tls);
    expect(adb.calls.any((args) => args.contains('unauth')), isFalse);
  });

  test('网络投屏启动时记住硬件序列号，TCP 失败后可切换 TLS', () async {
    const tcp = '192.168.1.8:5555';
    const tls = 'adb-phone-xyz._adb-tls-connect._tcp';
    final adb = TransportAdb()
      ..devices = '$tcp device\n$tls device'
      ..serials.addAll({tcp: 'phone', tls: 'phone'});
    final resolver = MirrorTransportResolver(adb, tcp);
    addTearDown(resolver.dispose);
    expect(await resolver.resolve(excluded: {tcp}), tls);
    expect(adb.calls.first, ['-s', tcp, 'shell', 'getprop', 'ro.serialno']);
  });

  test('USB 重新接上时按新列表优先 USB，不固定旧的无线地址', () async {
    const tcp = '192.168.1.8:5555';
    final adb = TransportAdb()
      ..devices = '$tcp device\nphone device\n192.168.1.9:5555 device'
      ..serials.addAll({
        tcp: 'phone',
        'phone': 'phone',
        '192.168.1.9:5555': 'phone',
      });
    final resolver = MirrorTransportResolver(adb, tcp);
    addTearDown(resolver.dispose);
    expect(await resolver.resolve(excluded: {tcp}), 'phone');
  });

  test('普通 TCP 和 TLS 均在线时优先普通 TCP', () async {
    const tls = 'adb-phone-xyz._adb-tls-connect._tcp';
    final adb = TransportAdb()
      ..devices = '$tls device\n192.168.1.8:5555 device'
      ..serials.addAll({tls: 'phone', '192.168.1.8:5555': 'phone'});
    final resolver = MirrorTransportResolver(adb, 'phone');
    addTearDown(resolver.dispose);
    expect(await resolver.resolve(excluded: {'phone'}), '192.168.1.8:5555');
  });

  test('DHCP 地址复用、相同型号或未知硬件身份不能切到其他手机', () async {
    final adb = TransportAdb()
      ..devices =
          '192.168.1.8:5555 device model:Fold\n192.168.1.9:5555 device model:Fold'
      ..serials['192.168.1.8:5555'] = 'other-phone';
    final resolver = MirrorTransportResolver(adb, 'phone');
    addTearDown(resolver.dispose);
    expect(await resolver.resolve(excluded: {'phone'}), isNull);
  });

  test('身份读取支持 ro.boot.serialno 回退', () async {
    final adb = TransportAdb()
      ..devices = '192.168.1.8:5555 device'
      ..bootSerials['192.168.1.8:5555'] = 'phone';
    final resolver = MirrorTransportResolver(adb, 'phone');
    addTearDown(resolver.dispose);
    expect(await resolver.resolve(excluded: {'phone'}), '192.168.1.8:5555');
  });

  test('每次恢复重新查询，动态端口变化后不使用上一次地址', () async {
    final adb = TransportAdb()
      ..devices = '192.168.1.8:37001 device'
      ..serials.addAll({
        '192.168.1.8:37001': 'phone',
        '192.168.1.8:38002': 'phone',
      });
    final resolver = MirrorTransportResolver(adb, 'phone');
    addTearDown(resolver.dispose);
    expect(await resolver.resolve(excluded: {'phone'}), '192.168.1.8:37001');
    adb.devices = '192.168.1.8:38002 device';
    expect(
      await resolver.resolve(excluded: {'192.168.1.8:37001'}),
      '192.168.1.8:38002',
    );
    expect(adb.calls.where((args) => args.first == 'devices'), hasLength(2));
  });

  test('列表失败、只有失败通道或初始网络身份未知时不自动启动', () async {
    final adb = TransportAdb()..listCode = 124;
    final resolver = MirrorTransportResolver(adb, 'phone');
    addTearDown(resolver.dispose);
    expect(await resolver.resolve(excluded: {'phone'}), isNull);
    adb.listCode = 0;
    adb.devices = 'phone device';
    expect(await resolver.resolve(excluded: {'phone'}), isNull);
    final unknown = MirrorTransportResolver(adb, '192.168.1.8:5555');
    addTearDown(unknown.dispose);
    expect(await unknown.resolve(excluded: {}), isNull);
  });

  test('窗口关闭后丢弃迟到的列表，也不继续查询候选', () async {
    final adb = TransportAdb()
      ..devices = '192.168.1.8:5555 device'
      ..listGate = Completer<void>();
    final resolver = MirrorTransportResolver(adb, 'phone');
    final pending = resolver.resolve(excluded: {'phone'});
    await Future<void>.delayed(Duration.zero);
    resolver.dispose();
    adb.listGate!.complete();
    expect(await pending, isNull);
    expect(adb.calls, [
      ['devices', '-l'],
    ]);
  });
}
