import 'dart:io';

import 'package:any_deck/core/dlna/dlna_discovery_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SSDP LOCATION 使用到手机路由的网卡地址，不使用 VPN 地址', () {
    final address = DlnaDiscoveryAddress.select(
      '   route to: 192.168.31.128\ninterface: en0\n',
      InternetAddress('192.168.31.128'),
      {
        'utun5': [InternetAddress('10.190.1.229')],
        'en0': [InternetAddress('192.168.31.12')],
      },
    );
    expect(address?.address, '192.168.31.12');
  });

  test('没有可用路由网卡时不公布其他网卡地址', () {
    final address = DlnaDiscoveryAddress.select(
      'interface: en7\n',
      InternetAddress('192.168.31.128'),
      {
        'utun5': [InternetAddress('10.190.1.229')],
      },
    );
    expect(address, isNull);
  });
}
