import 'dart:async';

import 'package:any_deck/core/airplay/airplay_mirror_window_coordinator.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:flutter_test/flutter_test.dart';

AirPlaySessionData session(AirPlayServerStatus status, {int id = 1}) =>
    AirPlaySessionData(
      id: id,
      serverName: 'test',
      rtspPort: 7000,
      videoPort: 7100,
      status: status,
      clientDeviceId: 'phone-$id',
    );

void main() {
  final now = DateTime(2026, 10, 27);
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test(
    'already connected mirror opens before first frame, without duplicate open',
    () async {
      final opened = <int>[];
      final coordinator = AirPlayMirrorWindowCoordinator(
        open: (s) async {
          opened.add(s.id);
          return true;
        },
      );
      coordinator.reconcile(session(AirPlayServerStatus.mirrorStarting), now);
      await settle();
      coordinator.reconcile(session(AirPlayServerStatus.mirroring), now);
      await settle();
      expect(opened, [1]);
    },
  );

  test('HTTP video and audio/idle never open phone windows', () async {
    var opens = 0;
    final coordinator = AirPlayMirrorWindowCoordinator(
      open: (_) async {
        opens++;
        return true;
      },
    );
    final video = session(
      AirPlayServerStatus.idle,
    ).copyWith(isVideoPlaying: true);
    coordinator.reconcile(video, now);
    coordinator.reconcile(session(AirPlayServerStatus.idle), now);
    await settle();
    expect(opens, 0);
    expect(video.hasAnyMirroring, false);
    expect(video.copyWith(width: 0).isVideoPlaying, true);
  });

  test(
    'failed open retries with backoff; in-flight open is single flight',
    () async {
      final first = Completer<bool>();
      var opens = 0;
      final coordinator = AirPlayMirrorWindowCoordinator(
        open: (_) {
          opens++;
          return opens == 1 ? first.future : Future.value(true);
        },
      );
      final mirror = session(AirPlayServerStatus.mirroring);
      coordinator.reconcile(mirror, now);
      coordinator.reconcile(mirror, now.add(const Duration(seconds: 10)));
      expect(opens, 1);
      first.complete(false);
      await settle();
      coordinator.reconcile(mirror, now.add(const Duration(seconds: 1)));
      expect(opens, 1);
      coordinator.reconcile(mirror, now.add(const Duration(seconds: 3)));
      await settle();
      coordinator.reconcile(mirror, now.add(const Duration(seconds: 5)));
      expect(opens, 2);
    },
  );

  test('reconnect and multiple mirror slots open independently', () async {
    final opened = <int>[];
    final coordinator = AirPlayMirrorWindowCoordinator(
      open: (s) async {
        opened.add(s.id);
        return true;
      },
    );
    coordinator.reconcile(
      session(AirPlayServerStatus.mirroring).copyWith(
        additionalSessions: [
          session(AirPlayServerStatus.mirrorStarting, id: 2),
        ],
      ),
      now,
    );
    await settle();
    coordinator.reconcile(null, now);
    coordinator.reconcile(session(AirPlayServerStatus.mirrorStarting), now);
    await settle();
    expect(opened, [1, 2, 1]);
  });

  test(
    'failed future is retried and stale completion cannot suppress reconnect',
    () async {
      final first = Completer<bool>();
      var opens = 0;
      final coordinator = AirPlayMirrorWindowCoordinator(
        open: (_) {
          opens++;
          if (opens == 1) return first.future;
          if (opens == 2) return Future.error(StateError('not ready'));
          return Future.value(true);
        },
      );
      final mirror = session(AirPlayServerStatus.mirroring);
      coordinator.reconcile(mirror, now);
      coordinator.reconcile(null, now);
      coordinator.reconcile(mirror, now);
      first.complete(true);
      await settle();
      coordinator.reconcile(mirror, now.add(const Duration(seconds: 3)));
      await settle();
      expect(opens, 3);
    },
  );
}
