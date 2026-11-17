import 'dart:async';
import 'dart:convert';

import 'package:any_deck/core/logging/app_log_recorder.dart';
import 'package:any_deck/core/nearby_share/share_core_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('跨chunk的Core失败只记录固定类别，保留EOF尾行', () async {
    final log = AppLogRecorder.instance;
    final previous = log.history.length;
    final stream = StreamController<List<int>>();
    final subscription = drainShareCoreErrors(stream.stream);
    stream.add(utf8.encode('Honor receive fail'));
    stream.add(utf8.encode('ed: honor_peer_closed\nHonor send failed: peer_cancelled\r\n'));
    stream.add(utf8.encode('Honor send failed: user_rejected'));
    await stream.close();
    await subscription.cancel();
    final added = log.history.skip(previous).toList();
    expect(added.length, 3);
    expect(added[0], contains('share_core: operation=receive reason=honor_peer_closed'));
    expect(added[1], contains('share_core: operation=send reason=peer_cancelled'));
    expect(added[2], contains('share_core: operation=send reason=user_rejected'));
  });

  test('原始文本和过长行丢弃，不影响下一行错误类别', () async {
    final log = AppLogRecorder.instance;
    final previous = log.history.length;
    final stream = StreamController<List<int>>();
    final subscription = drainShareCoreErrors(stream.stream);
    stream.add(utf8.encode('Honor receive failed: /synthetic/private/file.txt\n'));
    stream.add(utf8.encode('Honor receive failed: ${'x' * 1024}'));
    stream.add(utf8.encode('\nordinary synthetic output\nHonor receive failed: honor_finish_command\n'));
    await stream.close();
    await subscription.cancel();
    final added = log.history.skip(previous).toList();
    expect(added.length, 1);
    expect(added.single, contains('share_core: operation=receive reason=honor_finish_command'));
    expect(added.single, isNot(contains('private')));
    expect(added.single, isNot(contains('synthetic')));
  });
}
