import 'dart:io';

import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('按真实 netmask 计算广播地址', () {
    expect(
      ShareNetwork.broadcastFor(
        InternetAddress('192.168.31.12'),
        0xffffff00,
      ).address,
      '192.168.31.255',
    );
    expect(
      ShareNetwork.broadcastFor(
        InternetAddress('10.7.2.19'),
        0xfffffe00,
      ).address,
      '10.7.3.255',
    );
  });
}
