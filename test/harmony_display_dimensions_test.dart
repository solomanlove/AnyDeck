import 'package:any_deck/core/harmony/harmony_mirror_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 HarmonyOS 主屏尺寸的输出格式兼容与段落隔离。
void main() {
  test('简写 Display 段兼容缩进、CRLF 和大小写字段', () {
    final dump = [
      '  Display 0:',
      '\twidth: 1260',
      '  HEIGHT: 2720',
      '  rotation: 1',
    ].join('\r\n');
    expect(HarmonyMirrorService.parseDisplayDimensions(dump), (2720, 1260));
  });

  test('两种 Display 格式支持旋转枚举与角度，Rotation 优先于 Orientation', () {
    for (final header in [
      'Display 0:',
      '---------------- Display ID: 0 ----------------',
    ]) {
      for (final rotation in [0, 1, 2, 3, 90, 180, 270]) {
        final landscape = [1, 3, 90, 270].contains(rotation);
        final dump =
            '''
$header
  Width: 1260
  Height: 2720
  Orientation: ${landscape ? 0 : 1}
  rotation: $rotation
''';
        expect(
          HarmonyMirrorService.parseDisplayDimensions(dump),
          landscape ? (2720, 1260) : (1260, 2720),
          reason: '$header / Rotation: $rotation',
        );
      }
    }
  });

  test('缺少 Rotation 时兼容 Orientation，无方向字段时保留原宽高', () {
    expect(
      HarmonyMirrorService.parseDisplayDimensions(
        'Display 0:\n  Width: 1260\n  Height: 2720\n  orientation: 3\n',
      ),
      (2720, 1260),
    );
    expect(
      HarmonyMirrorService.parseDisplayDimensions(
        'Display 0:\n  Width: 2720\n  Height: 1260\n',
      ),
      (2720, 1260),
    );
  });

  test('主屏 Bounds 仍优先于简写 Display 和历史尺寸', () {
    const dump = '''
[history] width: 1260 height: 2720
---------------- Screen ID: 0 ----------------
Bounds<L,T,W,H>: 0, 0, 2776, 1224,
---------------- Screen ID: 1055 ----------------
Bounds<L,T,W,H>: 0, 0, 720, 1280,
Display 0:
  Width: 1260
  Height: 2720
  rotation: 0
''';
    expect(HarmonyMirrorService.parseDisplayDimensions(dump), (2776, 1224));
  });

  test('主屏不会借用后续 Display 或 Screen 的高度和旋转字段', () {
    for (final header in [
      'Display 0:',
      '---------------- Display ID: 0 ----------------',
    ]) {
      for (final nextHeader in [
        'Display 1055:',
        '---------------- Display ID: 1055 ----------------',
        '---------------- Screen ID: 1055 ----------------',
      ]) {
        expect(
          HarmonyMirrorService.parseDisplayDimensions(
            '$header\n  Width: 1260\n$nextHeader\n  Height: 2720\n',
          ),
          (null, null),
          reason: '$header -> $nextHeader',
        );
        expect(
          HarmonyMirrorService.parseDisplayDimensions(
            '$header\n  Width: 1260\n  Height: 2720\n'
            '$nextHeader\n  rotation: 1\n',
          ),
          (1260, 2720),
          reason: '$header -> $nextHeader',
        );
      }
    }
  });

  test('虚拟屏、缺失或非法尺寸不作为主屏尺寸', () {
    for (final dump in [
      '',
      'Display 1:\n  Width: 1260\n  Height: 2720\n',
      'Display 0:\n  Width: 0\n  Height: 2720\n',
      'Display 0:\n  Width: -1260\n  Height: 2720\n',
      'Display 0:\n  Width: 1260.5\n  Height: 2720\n',
      'Display 0:\n  Width: 1260\n  Height: 0\n',
      'Display 0:\n  Width:\n  Height: 2720\n',
    ]) {
      expect(HarmonyMirrorService.parseDisplayDimensions(dump), (
        null,
        null,
      ), reason: dump);
    }
  });
}
