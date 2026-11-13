import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/receiver/receiver_name_probe.dart';
import 'package:flutter_test/flutter_test.dart';

const _renderer = 'urn:schemas-upnp-org:device:MediaRenderer:1';

/// 使用确定性的命令输出与网络替身，验证重名判断和请求边界。
void main() {
  ReceiverSsdpReply reply({
    String uuid = 'remote',
    String location = 'http://192.168.1.8:18583/device.xml',
    String sender = '192.168.1.8',
    String target = _renderer,
  }) => ReceiverSsdpReply(
    sender: InternetAddress(sender),
    message:
        'HTTP/1.1 200 OK\r\nST: $target\r\n'
        'USN: uuid:$uuid::$_renderer\r\nLOCATION: $location\r\n\r\n',
  );

  String description(String name) =>
      '<root><device>'
      '<deviceType>$_renderer</deviceType>'
      '<friendlyName>$name</friendlyName></device></root>';

  Future<bool> check(ReceiverNameProbe probe, {String protocol = 'DLNA'}) =>
      probe.hasConflict(
        name: 'AnyDeck-办公室 Mac-DLNA',
        protocol: protocol,
        localUuid: 'local',
      );

  test('Bonjour 名称保留中文与空格，仅精确匹配 Add 记录', () async {
    const prefix = '12:34:56.000  Add  3  4 local. _airplay._tcp. ';
    const name = 'AnyDeck-办公室 Mac-AirPlay';
    final probe = ReceiverNameProbe(
      isMacOS: true,
      bonjourRunner: (_) async => ['$prefix$name Pro', '$prefix$name'],
    );
    expect(
      await probe.hasConflict(
        name: name,
        protocol: 'AirPlay',
        localUuid: 'local',
      ),
      isTrue,
    );
    expect(ReceiverNameProbe.bonjourName('$prefix$name'), name);
    expect(
      ReceiverNameProbe.bonjourName(
        '${prefix.replaceFirst('Add', 'Rmv')}$name',
      ),
      isNull,
    );
    final similar = ReceiverNameProbe(
      isMacOS: true,
      bonjourRunner: (_) async => ['$prefix$name Pro'],
    );
    expect(
      await similar.hasConflict(
        name: name,
        protocol: 'AirPlay',
        localUuid: 'local',
      ),
      isFalse,
    );
  });

  test('非 macOS 不启动 Bonjour，命令失败不阻止服务启动', () async {
    final unsupported = ReceiverNameProbe(
      isMacOS: false,
      bonjourRunner: (_) async => throw StateError('不应调用'),
    );
    expect(await check(unsupported, protocol: 'AirPlay'), isFalse);
    final failed = ReceiverNameProbe(
      isMacOS: true,
      bonjourRunner: (_) async => throw const ProcessException('dns-sd', []),
    );
    expect(await check(failed, protocol: 'AirPlay'), isFalse);
  });

  test('SSDP 排除本实例 UUID，兼容 uuid 前缀和大小写', () {
    expect(
      ReceiverNameProbe.ssdpLocation(
        reply(uuid: 'LOCAL'),
        localUuid: 'uuid:local',
      ),
      isNull,
    );
    expect(
      ReceiverNameProbe.ssdpLocation(reply(), localUuid: 'local'),
      Uri.parse('http://192.168.1.8:18583/device.xml'),
    );
  });

  test('SSDP 不接受不同主机、域名、重定向协议或非 Renderer', () {
    for (final invalid in [
      reply(location: 'http://192.168.1.9/device.xml'),
      reply(location: 'http://example.com/device.xml'),
      reply(location: 'https://192.168.1.8/device.xml'),
      reply(location: 'http://user:pass@192.168.1.8/device.xml'),
      reply(location: 'http://192.168.1.8/device.xml#fragment'),
      reply(location: 'http://8.8.8.8/device.xml', sender: '8.8.8.8'),
      reply(target: 'upnp:rootdevice'),
    ]) {
      expect(
        ReceiverNameProbe.ssdpLocation(invalid, localUuid: 'local'),
        isNull,
      );
    }
  });

  test('DLNA XML 解码实体，拒绝错误文档和 DTD', () {
    expect(
      ReceiverNameProbe.friendlyName(
        description('AnyDeck-研发 &amp; 测试-&#68;LNA'),
      ),
      'AnyDeck-研发 & 测试-DLNA',
    );
    expect(ReceiverNameProbe.friendlyName('<root>'), isNull);
    expect(
      ReceiverNameProbe.friendlyName('<!DOCTYPE root>${description('名称')}'),
      isNull,
    );
    expect(
      ReceiverNameProbe.friendlyName(
        description('名称').replaceFirst(_renderer, 'upnp:rootdevice'),
      ),
      isNull,
    );
  });

  test('DLNA 精确匹配设备描述，排除本机且同一 LOCATION 只读取一次', () async {
    final requested = <Uri>[];
    final probe = ReceiverNameProbe(
      ssdpSearch: (_) async => [reply(uuid: 'local'), reply(), reply()],
      descriptionReader: (location, _) async {
        requested.add(location);
        return description('AnyDeck-办公室 Mac-DLNA');
      },
    );
    expect(await check(probe), isTrue);
    expect(requested.length, 1);
    final similar = ReceiverNameProbe(
      ssdpSearch: (_) async => [reply()],
      descriptionReader: (_, _) async =>
          description('AnyDeck-办公室 Mac-DLNA Pro'),
    );
    expect(await check(similar), isFalse);
  });

  test('DLNA 描述错误不影响其他设备，HTTP 读取数最多八个', () async {
    var reads = 0;
    final probe = ReceiverNameProbe(
      ssdpSearch: (_) async => List.generate(
        20,
        (index) => reply(
          uuid: 'remote$index',
          location: 'http://192.168.1.8:18583/device$index.xml',
        ),
      ),
      descriptionReader: (_, _) async {
        reads++;
        if (reads == 1) throw const HttpException('设备离线');
        return description('AnyDeck-办公室 Mac-DLNA');
      },
    );
    expect(await check(probe), isTrue);
    expect(reads, 8);
  });

  test('DLNA 网络无权限、描述超时或超限均安全返回 false', () async {
    final denied = ReceiverNameProbe(
      ssdpSearch: (_) async => throw const SocketException('无局域网权限'),
    );
    expect(await check(denied), isFalse);
    final hanging = ReceiverNameProbe(
      timeout: const Duration(milliseconds: 30),
      ssdpSearch: (_) async => [reply()],
      descriptionReader: (_, _) => Completer<String?>().future,
    );
    expect(await check(hanging).timeout(const Duration(seconds: 1)), isFalse);
    final oversized = ReceiverNameProbe(
      ssdpSearch: (_) async => [reply()],
      descriptionReader: (_, _) async => 'a' * (64 * 1024 + 1),
    );
    expect(await check(oversized), isFalse);
  });

  test('DLNA 扫描到期后的轻量收尾仍保留已经发现的设备', () async {
    final probe = ReceiverNameProbe(
      timeout: const Duration(milliseconds: 200),
      ssdpSearch: (budget) => Future.delayed(
        budget + const Duration(milliseconds: 5),
        () => [reply()],
      ),
      descriptionReader: (_, _) async => description('AnyDeck-办公室 Mac-DLNA'),
    );
    expect(await check(probe), isTrue);
  });
}
