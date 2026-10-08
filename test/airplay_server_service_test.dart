import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';

void main() {
  group('AirPlayServerState Tests', () {
    test('AirPlayServerStatus raw mapping is correct', () {
      expect(AirPlayServerStatus.fromRaw(0), AirPlayServerStatus.idle);
      expect(AirPlayServerStatus.fromRaw(1), AirPlayServerStatus.mirroring);
      expect(AirPlayServerStatus.fromRaw(2), AirPlayServerStatus.stopped);
      expect(AirPlayServerStatus.fromRaw(99), AirPlayServerStatus.stopped);
    });

    test('AirPlaySessionData copyWith works as expected', () {
      const session = AirPlaySessionData(
        id: 1001,
        serverName: 'AnyDeck-Test',
        rtspPort: 7000,
        videoPort: 7100,
        status: AirPlayServerStatus.idle,
        width: 1080,
        height: 1920,
        textureId: 42,
      );

      final updated = session.copyWith(
        status: AirPlayServerStatus.mirroring,
        width: 1170,
        height: 2532,
      );

      expect(updated.id, 1001);
      expect(updated.serverName, 'AnyDeck-Test');
      expect(updated.status, AirPlayServerStatus.mirroring);
      expect(updated.width, 1170);
      expect(updated.height, 2532);
      expect(updated.textureId, 42);
    });
  });
}
