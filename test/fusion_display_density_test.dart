import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/scrcpy/fusion_display_density.dart';
import 'package:any_deck/core/scrcpy/fusion_display_resize.dart';
import 'package:flutter_test/flutter_test.dart';

class _ResizingAdbFake extends AdbService {
  _ResizingAdbFake(this.target) : super(executable: 'adb');

  final FusionDisplayGeometry target;
  final commands = <List<String>>[];
  int sizeReads = 0;

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    if (args[1] == 'size') {
      sizeReads++;
      return AdbResult(
        exitCode: 0,
        stdout: sizeReads == 1
            ? 'Physical size: 1600x1106\n'
            : 'Physical size: ${target.width}x${target.height}\n',
        stderr: '',
      );
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  test('等 VirtualDisplay 完成 resize 后才更新 density', () async {
    final target = FusionDisplayGeometry.fromViewport(688, 780);
    final adb = _ResizingAdbFake(target);

    final applied = await FusionDisplayDensity.applyWhenResized(
      adbService: adb,
      deviceId: 'phone',
      displayId: 122,
      geometry: target,
    );

    expect(applied, isTrue);
    expect(adb.commands, [
      ['wm', 'size', '-d', '122'],
      ['wm', 'size', '-d', '122'],
      ['wm', 'density', '${target.densityDpi}', '-d', '122'],
    ]);
  });
}
