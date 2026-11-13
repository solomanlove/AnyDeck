import 'dart:async';

import 'package:any_deck/core/airplay/airplay_publication.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('异步冲突期间等待，成功后只返回确认的稳定后备名称', () async {
    var reads = 0;
    final name = await waitForAirplayPublication(
      readStatus: () => ++reads >= 3 ? 1 : 0,
      readName: () => 'AnyDeck-Meeting-AABBCC112233-AirPlay',
      interval: const Duration(milliseconds: 1),
    );
    expect(name, 'AnyDeck-Meeting-AABBCC112233-AirPlay');
    expect(reads, 3);
  });

  test('最终冲突失败和无法确认名称都不报告请求名为成功', () async {
    await expectLater(
      waitForAirplayPublication(readStatus: () => 2, readName: () => '请求名称'),
      throwsStateError,
    );
    await expectLater(
      waitForAirplayPublication(
        readStatus: () => 1,
        readName: () => null,
        timeout: const Duration(milliseconds: 5),
        interval: const Duration(milliseconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('运行中重新发布不改变活跃媒体状态，待机发布必须已确认', () {
    const idle = AirPlaySessionData(
      id: 1,
      serverName: '原名称',
      rtspPort: 7000,
      videoPort: 7100,
      status: AirPlayServerStatus.idle,
    );
    final waiting = idle.copyWith(isPublished: false);
    expect(waiting.hasAnyBroadcasting, isFalse);
    final active = waiting.copyWith(
      status: AirPlayServerStatus.mirroring,
      clientDeviceId: 'phone',
    );
    final renamed = active.copyWith(serverName: '稳定后备名', isPublished: true);
    expect(renamed.hasAnyMirroring, isTrue);
    expect(renamed.clientDeviceId, 'phone');
    expect(renamed.serverName, '稳定后备名');
    expect(renamed.id, active.id);
    expect(renamed.rtspPort, active.rtspPort);
  });
}
