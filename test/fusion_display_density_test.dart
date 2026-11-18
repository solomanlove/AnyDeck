import 'dart:async';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/scrcpy/fusion_display_density.dart';
import 'package:any_deck/core/scrcpy/fusion_display_resize.dart';
import 'package:flutter_test/flutter_test.dart';

const _ok = AdbResult(exitCode: 0, stdout: '', stderr: '');

/// 模拟荣耀普通 density 接口会联动内屏，比例接口只更新目标副屏。
class _DensityAdbFake extends AdbService {
  _DensityAdbFake(this.target) : super(executable: 'adb');

  FusionDisplayGeometry target;
  String manufacturer = 'HONOR';
  bool supportsRatio = true;
  AdbResult? manufacturerResult;
  AdbResult densityResult = _ok;
  int staleSizeReads = 0;
  int sizeReads = 0;
  int phoneDpi = 480;
  int innerDpi = 480;
  int virtualDpi = 197;
  final commands = <List<String>>[];
  final densityStarted = Completer<void>();
  final sizeStarted = Completer<void>();
  Completer<AdbResult>? pendingDensity;
  Completer<AdbResult>? pendingSize;

  List<List<String>> get writes =>
      commands.where((args) => args[1] == 'density').toList();

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    if (args.first == 'getprop') {
      return manufacturerResult ??
          AdbResult(exitCode: 0, stdout: '$manufacturer\n', stderr: '');
    }
    if (args[1] == 'help') {
      return AdbResult(
        exitCode: 0,
        stdout:
            '  density [reset|DENSITY] [-d DISPLAY_ID]'
            '${supportsRatio ? ' [-r]' : ''}\n  unrelated-command [-r]\n',
        stderr: '',
      );
    }
    if (args[1] == 'size') {
      sizeReads++;
      if (!sizeStarted.isCompleted) sizeStarted.complete();
      if (pendingSize != null) return pendingSize!.future;
      return AdbResult(
        exitCode: 0,
        stdout: sizeReads <= staleSizeReads
            ? 'Physical size: 1600x1106\n'
            : 'Physical size: ${target.width}x${target.height}\n',
        stderr: '',
      );
    }
    if (args[2] == 'reset') {
      virtualDpi = 197;
      return _ok;
    }
    virtualDpi = int.parse(args[2]);
    if (!args.contains('-r') && manufacturer == 'HONOR') {
      phoneDpi = innerDpi = virtualDpi;
    }
    if (!densityStarted.isCompleted) densityStarted.complete();
    return pendingDensity?.future ?? densityResult;
  }
}

FusionDisplayDensity _session(_DensityAdbFake adb) =>
    FusionDisplayDensity(adbService: adb, deviceId: 'phone', displayId: 122);

void main() {
  test('等副屏 resize 完成后才写入独立比例 DPI', () async {
    final target = FusionDisplayGeometry.fromViewport(688, 780);
    final adb = _DensityAdbFake(target)..staleSizeReads = 1;
    final density = _session(adb);
    addTearDown(density.restore);

    expect(await density.applyWhenResized(geometry: target), isTrue);
    expect(adb.sizeReads, 2);
    expect(adb.writes, [
      ['wm', 'density', '${target.densityDpi}', '-d', '122', '-r'],
    ]);
    expect(adb.commands.last, adb.writes.single);
  });

  test('荣耀副屏来回缩放保持内外屏 DPI，能力探测在会话内复用', () async {
    final portrait = FusionDisplayGeometry.fromViewport(688, 780);
    final landscape = FusionDisplayGeometry.fromViewport(1200, 688);
    final adb = _DensityAdbFake(portrait);
    final density = _session(adb);
    addTearDown(density.restore);

    for (final target in [portrait, landscape, portrait]) {
      adb.target = target;
      expect(await density.applyWhenResized(geometry: target), isTrue);
      expect(adb.virtualDpi, target.densityDpi);
      expect(adb.phoneDpi, 480);
      expect(adb.innerDpi, 480);
    }
    expect(adb.commands.where((args) => args[1] == 'help'), hasLength(1));
    expect(adb.commands.where((args) => args.first == 'getprop'), hasLength(1));
  });

  test('不支持比例接口的普通 Android 保持指定副屏的兼容写法', () async {
    const target = FusionDisplayGeometry(1600, 924, 114);
    final adb = _DensityAdbFake(target)
      ..manufacturer = 'Google'
      ..supportsRatio = false;
    final density = _session(adb);
    addTearDown(density.restore);

    expect(await density.applyWhenResized(geometry: target), isTrue);
    expect(adb.writes.single, ['wm', 'density', '114', '-d', '122']);
    expect(adb.phoneDpi, 480);
  });

  for (final manufacturer in ['HONOR', 'HUAWEI']) {
    test('$manufacturer 缺少比例接口时禁止普通 DPI 回退', () async {
      const target = FusionDisplayGeometry(1600, 924, 114);
      final adb = _DensityAdbFake(target)
        ..manufacturer = manufacturer
        ..supportsRatio = false;
      final density = _session(adb);

      expect(await density.applyWhenResized(geometry: target), isFalse);
      expect(await density.restore(), isTrue);
      expect(adb.writes, isEmpty);
      expect(adb.phoneDpi, 480);
      expect(adb.innerDpi, 480);
    });
  }

  test('无法确认厂商且没有比例接口时不写入 DPI', () async {
    const target = FusionDisplayGeometry(1600, 924, 114);
    final adb = _DensityAdbFake(target)
      ..supportsRatio = false
      ..manufacturerResult = const AdbResult(
        exitCode: 124,
        stdout: '',
        stderr: 'Timeout',
      );
    final density = _session(adb);

    expect(await density.applyWhenResized(geometry: target), isFalse);
    expect(await density.restore(), isTrue);
    expect(adb.writes, isEmpty);
  });

  test('窗口在尺寸查询期间失效后不写入或重置副屏', () async {
    const target = FusionDisplayGeometry(1600, 924, 114);
    final adb = _DensityAdbFake(target)..pendingSize = Completer<AdbResult>();
    final density = _session(adb);
    var current = true;
    final update = density.applyWhenResized(
      geometry: target,
      isCurrent: () => current,
    );
    await adb.sizeStarted.future;

    current = false;
    adb.pendingSize!.complete(
      const AdbResult(
        exitCode: 0,
        stdout: 'Physical size: 1600x924',
        stderr: '',
      ),
    );

    expect(await update, isFalse);
    expect(await density.restore(), isTrue);
    expect(adb.writes, isEmpty);
  });

  test('关闭等待在途写入并取消排队更新，再只重置原副屏一次', () async {
    const target = FusionDisplayGeometry(1600, 924, 114);
    final adb = _DensityAdbFake(target)
      ..pendingDensity = Completer<AdbResult>();
    final density = _session(adb);
    final first = density.applyWhenResized(geometry: target);
    await adb.densityStarted.future;
    final queued = density.applyWhenResized(geometry: target);
    final closing = density.restore();
    expect(adb.writes, hasLength(1));

    adb.pendingDensity!.complete(_ok);

    expect(await first, isTrue);
    expect(await queued, isFalse);
    expect(await closing, isTrue);
    expect(await density.restore(), isTrue);
    expect(await density.applyWhenResized(geometry: target), isFalse);
    expect(adb.writes, [
      ['wm', 'density', '114', '-d', '122', '-r'],
      ['wm', 'density', 'reset', '-d', '122'],
    ]);
    expect(adb.virtualDpi, 197);
    expect(adb.phoneDpi, 480);
    expect(adb.innerDpi, 480);
  });

  test('写入超时后仍还原可能已生效的副屏 DPI', () async {
    const target = FusionDisplayGeometry(1600, 924, 114);
    final adb = _DensityAdbFake(target)
      ..densityResult = const AdbResult(
        exitCode: 124,
        stdout: '',
        stderr: 'Timeout',
      );
    final density = _session(adb);

    expect(await density.applyWhenResized(geometry: target), isFalse);
    expect(adb.virtualDpi, 114);
    expect(await density.restore(), isTrue);
    expect(adb.virtualDpi, 197);
    expect(adb.writes.last, ['wm', 'density', 'reset', '-d', '122']);
  });

  test('比例接口返回错误时不误报成功或回退到普通 density', () async {
    const target = FusionDisplayGeometry(1600, 924, 114);
    final adb = _DensityAdbFake(target)
      ..densityResult = const AdbResult(
        exitCode: 0,
        stdout: '',
        stderr: 'Error: display unavailable',
      );
    final density = _session(adb);
    addTearDown(density.restore);

    expect(await density.applyWhenResized(geometry: target), isFalse);
    expect(adb.writes, hasLength(1));
    expect(adb.writes.single.last, '-r');
    expect(adb.phoneDpi, 480);
  });

  for (final displayId in [0, -1]) {
    test('拒绝将 $displayId 当成融合副屏', () {
      expect(
        () => FusionDisplayDensity(
          adbService: _DensityAdbFake(
            const FusionDisplayGeometry(1600, 924, 114),
          ),
          deviceId: 'phone',
          displayId: displayId,
        ),
        throwsArgumentError,
      );
    });
  }
}
