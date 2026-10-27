import 'package:any_deck/core/airplay/airplay_connection_monitor.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('短暂 Idle 不断线，持续 Idle 报断线，恢复后重新计时', () {
    final monitor = AirPlayConnectionMonitor();
    final now = DateTime(2026, 10, 16);
    expect(monitor.isDisconnected(AirPlayServerStatus.idle, now), false);
    expect(monitor.isDisconnected(AirPlayServerStatus.idle,
        now.add(const Duration(seconds: 3))), true);
    expect(monitor.isDisconnected(AirPlayServerStatus.mirroring,
        now.add(const Duration(seconds: 4))), false);
    expect(monitor.isDisconnected(AirPlayServerStatus.idle,
        now.add(const Duration(seconds: 5))), false);
  });

  test('镜像等待首帧不会当作 Idle 断线', () {
    final monitor = AirPlayConnectionMonitor();
    final now = DateTime(2026);
    expect(monitor.isDisconnected(AirPlayServerStatus.mirrorStarting, now), false);
    expect(monitor.isDisconnected(AirPlayServerStatus.mirrorStarting,
        now.add(const Duration(seconds: 10))), false);
  });

  test('明确停止立即断线', () {
    expect(AirPlayConnectionMonitor().isDisconnected(
        AirPlayServerStatus.stopped, DateTime(2026)), true);
  });
}
