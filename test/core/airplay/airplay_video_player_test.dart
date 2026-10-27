import 'dart:async';

import 'package:any_deck/core/airplay/airplay_video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late List<(int, int, Map<dynamic, dynamic>)> reports;
  late Map<String, dynamic> command;
  late AirPlayVideoPlayer player;
  int nativeGeneration = 0;
  Completer<void>? pendingPlay;

  setUp(() {
    calls = [];
    reports = [];
    command = {
      'generation': 1,
      'revision': 1,
      'seek_revision': 1,
      'url': 'https://example.test/movie.m3u8',
      'start': 8.0,
      'rate': 1.0,
    };
    pendingPlay = null;
    messenger.setMockMethodCallHandler(AirPlayVideoPlayer.channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'playUrl') {
        nativeGeneration = (call.arguments as Map)['generation'] as int;
        await pendingPlay?.future;
      }
      if (call.method == 'playbackState') {
        return {
          'generation': nativeGeneration,
          'duration': 120.0,
          'position': 8.5,
          'rate': 1.0,
          'state': 1,
        };
      }
      return null;
    });
    player = AirPlayVideoPlayer(
      read: (_) => Map<String, dynamic>.from(command),
      report: (h, g, state) => reports.add((h, g, state)),
    );
  });

  tearDown(() async {
    await player.stop();
    messenger.setMockMethodCallHandler(AirPlayVideoPlayer.channel, null);
  });

  test(
    'video opens a separate native window and reports actual progress',
    () async {
      await player.start(1000, 'Test AirPlay');
      await player.poll();
      final open =
          calls.singleWhere((c) => c.method == 'playUrl').arguments as Map;
      expect(open['url'], command['url']);
      expect(open['position'], 8.0);
      expect(
        calls.any(
          (c) => c.method == 'setTitle' && c.arguments == 'Test AirPlay',
        ),
        isTrue,
      );
      expect(reports.single.$1, 1000);
      expect(reports.single.$3['position'], 8.5);
      await player.poll();
      expect(calls.where((c) => c.method == 'playUrl'), hasLength(1));
    },
  );

  test('pause seek resume stop and new source reuse the same player', () async {
    await player.start(1000, 'AirPlay');
    await player.poll();
    command.addAll({'revision': 2, 'rate': 0.0});
    await player.poll();
    expect(calls.lastWhere((c) => c.method == 'setRate').arguments, 0.0);
    command.addAll({'revision': 3, 'seek_revision': 2, 'start': 50.0});
    await player.poll();
    expect(calls.lastWhere((c) => c.method == 'seek').arguments, 50.0);
    command.addAll({'revision': 4, 'rate': 1.0});
    await player.poll();
    expect(calls.lastWhere((c) => c.method == 'setRate').arguments, 1.0);
    command.addAll({'revision': 5, 'url': null});
    await player.poll();
    expect(calls.last.method, 'close');
    command.addAll({
      'revision': 6,
      'generation': 2,
      'url': 'https://example.test/b.mp4',
    });
    await player.poll();
    expect(calls.where((c) => c.method == 'playUrl'), hasLength(2));
    expect(reports.last.$2, 2);
  });

  test(
    'stop during asynchronous open waits then closes without stale reports',
    () async {
      await player.start(1000, 'AirPlay');
      pendingPlay = Completer<void>();
      final poll = player.poll();
      await Future<void>.delayed(Duration.zero);
      final stopping = player.stop();
      pendingPlay!.complete();
      await Future.wait([poll, stopping]);
      expect(calls.last.method, 'close');
      expect(reports, isEmpty);
    },
  );

  test('video activity and localized title stay separate from mirror windows', () async {
    final activity = <bool>[];
    player = AirPlayVideoPlayer(
      read: (_) => Map<String, dynamic>.from(command),
      report: (_, _, _) {},
      onActivityChanged: activity.add,
    );
    await player.start(1000, 'Receiver');
    await player.setLabels(loading: 'Loading', failure: 'Failed', pin: 'Pin',
        unpin: 'Unpin', title: 'Receiver · AirPlay 视频');
    await player.poll();
    await player.showWindow();
    expect(calls.last.method, 'show');
    expect(calls.lastWhere((c) => c.method == 'setTitle').arguments,
        'Receiver · AirPlay 视频');
    command.addAll({'revision': 2, 'url': null});
    await player.poll();
    expect(activity, [true, false]);
    final count = calls.length;
    await player.showWindow();
    expect(calls.length, count);
  });

  test('non HTTP source never opens and reports failure', () async {
    command['url'] = 'file:///etc/hosts';
    await player.start(1000, 'AirPlay');
    await player.poll();
    expect(calls.where((c) => c.method == 'playUrl'), isEmpty);
    expect(reports.single.$3['state'], 2);
  });

  test(
    'user closes window and old generation events cannot stop new media',
    () async {
      await player.start(1000, 'AirPlay');
      await player.poll();
      final old = nativeGeneration;
      command.addAll({'generation': 2, 'revision': 2});
      await player.poll();
      reports.clear();
      Future<void> emit(int generation) async {
        await messenger.handlePlatformMessage(
          AirPlayVideoPlayer.channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('playerStopped', {'generation': generation}),
          ),
          (_) {},
        );
      }

      await emit(old);
      expect(reports, isEmpty);
      await emit(nativeGeneration);
      expect(reports.single.$2, 2);
      expect(reports.single.$3['state'], 2);
    },
  );

  test(
    'old open failure never marks a newer pending source as failed',
    () async {
      messenger.setMockMethodCallHandler(AirPlayVideoPlayer.channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'playUrl') {
          command.addAll({'generation': 2, 'revision': 2});
          throw PlatformException(code: 'old_media_failed');
        }
        return null;
      });
      await player.start(1000, 'AirPlay');
      await player.poll();
      expect(reports.single.$2, 1);
      expect(reports.single.$3['state'], 2);
      expect(calls.last.method, 'close');
    },
  );

  test('audio-only idle snapshot does not create a video window', () async {
    command.addAll({'generation': 0, 'revision': 0, 'url': null});
    await player.start(1000, 'AirPlay');
    await player.poll();
    expect(calls.where((c) => c.method == 'playUrl'), isEmpty);
    expect(reports, isEmpty);
  });
}
