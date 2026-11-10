import 'dart:async';

import 'package:any_deck/core/scrcpy/rust_host_recording.dart';
import 'package:any_deck/core/scrcpy/rust_recording_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟原生状态机，验证 Dart 不会在 MP4 收尾之前报告保存成功。
class _Native implements RecordingNativeApi {
  int state = 1;
  int starts = 0;
  int stops = 0;
  int releases = 0;
  String failure = '';
  bool finalizeOnStop = true;
  List<String>? arguments;
  @override
  int start(String adb, String serial, String jar, String path) {
    starts++;
    arguments = [adb, serial, jar, path];
    return 7;
  }

  @override
  int status(int handle) => state;
  @override
  String error(int handle) => failure;
  @override
  void stop(int handle) {
    stops++;
    if (finalizeOnStop && state < 2) state = 2;
  }

  @override
  void release(int handle) {
    releases++;
  }
}

void main() {
  RustHostRecording create(
    _Native native,
    List<String> lifecycle, {
    Future<String> Function()? jar,
    Duration stopTimeout = const Duration(seconds: 1),
  }) => RustHostRecording(
    adb: '/fake/adb',
    deviceId: 'device:123',
    path: '/tmp/测试 video.mp4',
    resolveJar: jar ?? () async => '/app/server.jar',
    nativeFactory: () => native,
    lifecycle: (method, handle) async {
      lifecycle.add('$method:$handle');
    },
    startTimeout: const Duration(milliseconds: 200),
    stopTimeout: stopTimeout,
  );

  test('启动与停止幂等，原生收尾完成后才释放窗口句柄', () async {
    final native = _Native();
    final calls = <String>[];
    final recording = create(native, calls);
    await Future.wait([recording.start(), recording.start()]);
    expect(native.starts, 1);
    expect(native.arguments, [
      '/fake/adb',
      'device:123',
      '/app/server.jar',
      '/tmp/测试 video.mp4',
    ]);
    await Future.wait([recording.stop(), recording.stop()]);
    expect(native.releases, 1);
    expect(calls, ['track:7', 'untrack:7']);
    expect(await recording.exited, isNull);
  });

  test('停止等待文件收尾，不能提前返回成功', () async {
    final native = _Native()..finalizeOnStop = false;
    final recording = create(native, []);
    await recording.start();
    var finished = false;
    final stop = recording.stop().then((_) {
      finished = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(finished, isFalse);
    expect(native.releases, 0);
    native.state = 2;
    await stop;
    expect(native.releases, 1);
  });

  test('写盘或断线失败通过退出结果和 stop 传播', () async {
    final native = _Native();
    final recording = create(native, []);
    await recording.start();
    native
      ..state = 3
      ..failure = 'disk full; partial file: /tmp/test.partial.mp4';
    expect(await recording.exited, contains('disk full'));
    await expectLater(recording.stop(), throwsStateError);
    expect(native.releases, 1);
  });

  test('启动失败也清理原生资源并注销窗口跟踪', () async {
    final messages = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => messages.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
    final native = _Native()
      ..state = 3
      ..failure = 'bad codec';
    final calls = <String>[];
    final recording = create(native, calls);
    await expectLater(recording.start(), throwsStateError);
    expect(messages, contains(contains('[HostRecording] Start failed:')));
    expect(messages.join('\n'), contains('bad codec'));
    expect(native.releases, 1);
    expect(calls, ['track:7', 'untrack:7']);
    await recording.stop();
    expect(native.releases, 1);
  });

  test('提取 JAR 期间取消，不启动迟到的原生录制', () async {
    final native = _Native();
    final jar = Completer<String>();
    final recording = create(native, [], jar: () => jar.future);
    final start = recording.start();
    final failure = expectLater(start, throwsStateError);
    final stop = recording.stop();
    jar.complete('/app/server.jar');
    await failure;
    await stop;
    expect(native.starts, 0);
  });

  test('收尾超时明确失败且释放句柄', () async {
    final native = _Native()..finalizeOnStop = false;
    final recording = create(
      native,
      [],
      stopTimeout: const Duration(milliseconds: 50),
    );
    await recording.start();
    await expectLater(recording.stop(), throwsStateError);
    expect(native.releases, 1);
  });
}
