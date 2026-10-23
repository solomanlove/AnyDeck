import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/dlna/dlna_protocol.dart';

void main() {
  test('设备描述声明 MediaRenderer 与控制服务', () {
    final xml = DlnaProtocol.deviceDescription('http://192.168.1.2:1234');
    expect(xml, contains(DlnaProtocol.deviceType));
    expect(xml, contains('http://192.168.1.2:1234/'));
    expect(xml, contains('/avtransport/control'));
    expect(xml, contains('/rendering/control'));
    expect(xml, contains('/connection/control'));
    expect(DlnaProtocol.searchTargets, contains(DlnaProtocol.transportType));
  });

  test('AVTransport 描述包含输入参数和状态变量', () {
    final xml = DlnaProtocol.serviceDescription('avtransport');
    expect(xml, contains('<name>SetAVTransportURI</name>'));
    expect(xml, contains('<name>CurrentURI</name><direction>in</direction>'));
    expect(xml, contains('<name>A_ARG_TYPE_CurrentURI</name>'));
  });

  test('SOAP URI 解码并拒绝实体声明', () {
    final body =
        '<u:CurrentURI>https://example.com/video?a=1&amp;b=2</u:CurrentURI>';
    expect(
      DlnaProtocol.element(body, 'CurrentURI'),
      'https://example.com/video?a=1&b=2',
    );
    expect(
      DlnaProtocol.element(
        '<!DOCTYPE x><CurrentURI>x</CurrentURI>',
        'CurrentURI',
      ),
      isNull,
    );
  });

  test('时间解析与格式化用于 Seek 和进度', () {
    expect(DlnaProtocol.parseTime('01:02:03.5'), 3723.5);
    expect(DlnaProtocol.formatTime(3723.5), '01:02:03');
    expect(DlnaProtocol.parseTime('00:99:00'), isNull);
  });
}
