import 'package:any_deck/core/device_info/android_display_parser.dart';
import 'package:any_deck/core/device_info/foldable_display_info.dart';
import 'package:any_deck/core/device_info/foldable_display_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/foldable_display_fixtures.dart';

/// 验证物理屏识别边界，不使用逻辑 ID、连接状态或设备型号猜测尺寸。
void main() {
  test('荣耀实机快照同时读取点亮内屏和熄灭外屏，忽略 scrcpy', () {
    final result = FoldableDisplayParser.parse(
      honorFoldableDisplayDump,
      deviceStates: honorFoldableStates,
    );
    expect(result?.innerResolution, '2352x2172');
    expect(result?.outerResolution, '2420x1080');
  });

  test('折叠切换、枚举倒序和 CRLF 不交换内外屏标签', () {
    final folded = honorFoldableDisplayDump
        .replaceAll('state ON', 'state DOZE')
        .replaceAll('state OFF', 'state ON')
        .replaceAll('type INTERNAL', 'type BUILT_IN')
        .split('\n')
        .reversed
        .join('\r\n');
    final result = FoldableDisplayParser.parse(
      folded,
      deviceStates: honorFoldableStates,
    );
    expect(result?.innerResolution, '2352x2172');
    expect(result?.outerResolution, '2420x1080');
  });

  test('Samsung 内屏自然方向为横向时保留高乘宽约定', () {
    final result = FoldableDisplayParser.parse(
      samsungFoldableDisplayDump,
      deviceStates: "name='CLOSED', name='OPENED'",
    );
    expect(result?.innerResolution, '1848x2448');
    expect(result?.outerResolution, '1972x1248');
  });

  test('支持翻盖折叠机的小尺寸外屏', () {
    final result = FoldableDisplayParser.parse(
      '${_panel('1', 1080, 2640)}\n${_panel('2', 720, 748)}',
      deviceStates: "name='FOLDED', name='UNFOLDED'",
    );
    expect(result?.innerResolution, '2640x1080');
    expect(result?.outerResolution, '748x720');
  });

  test('厂商折叠属性可在旧系统状态命令不可用时识别', () {
    for (final properties in [
      {'ro.vendor.display.supportfold': '1'},
      {'ro.config.fold_disp': '2420,0,1080,0,2172,2352'},
    ]) {
      expect(
        FoldableDisplayParser.parse(
          honorFoldableDisplayDump,
          properties: properties,
          deviceStates: 'Unknown command: print-states',
        )?.outerResolution,
        '2420x1080',
      );
    }
  });

  test('没有折叠证据的双屏设备不标记内外屏', () {
    expect(FoldableDisplayParser.parse(honorFoldableDisplayDump), isNull);
    expect(
      FoldableDisplayParser.parse(
        honorFoldableDisplayDump,
        properties: {'ro.config.fold_disp': 'unknown'},
        deviceStates: "name='DEFAULT'",
      ),
      isNull,
    );
  });

  test('明确的内外屏名称优先于像素面积', () {
    final result = FoldableDisplayParser.parse(
      '${_panel('1', 1080, 1920, name: 'Inner Screen')}\n'
      '${_panel('2', 1440, 2560, name: 'Cover Screen')}',
    );
    expect(result?.innerResolution, '1920x1080');
    expect(result?.outerResolution, '2560x1440');
  });

  test('按真实 DPI 计算面积，避免把低像素密度的内屏误标为外屏', () {
    final result = FoldableDisplayParser.parse(
      '${_panel('1', 1000, 2000, extra: '200.0 x 200.0 dpi,')}\n'
      '${_panel('2', 1500, 2500, extra: '500.0 x 500.0 dpi,')}',
      deviceStates: honorFoldableStates,
    );
    expect(result?.innerResolution, '2000x1000');
    expect(result?.outerResolution, '2500x1500');
  });

  test('同一块屏的刷新率和低分辨率模式不生成额外屏幕', () {
    final dump =
        '${_panel('1', 1080, 1200, extra: 'supportedModes '
            '[{id=1, width=1080, height=1200}, '
            '{id=2, width=2172, height=2352}, '
            '{id=3, width=2172, height=2352}],')}\n'
        '${_panel('2', 1080, 2420)}';
    final result = FoldableDisplayParser.parse(
      dump,
      deviceStates: honorFoldableStates,
    );
    expect(result?.innerResolution, '2352x2172');
    expect(result?.outerResolution, '2420x1080');
  });

  test('单物理屏、重复快照、外接屏和虚拟屏不组成折叠双屏', () {
    final single = _panel('1', 1080, 2400);
    for (final dump in [
      single,
      '$single\n$single',
      '$single\n${_panel('2', 2000, 3000).replaceAll('INTERNAL', 'EXTERNAL')}',
      '$single\n${_panel('2', 2000, 3000).replaceAll('local:', 'virtual:')}',
    ]) {
      expect(
        FoldableDisplayParser.parse(dump, deviceStates: honorFoldableStates),
        isNull,
      );
    }
  });

  test('尺寸缺失、等大双屏、三屏及命令失败时回退原概览', () {
    for (final dump in [
      '',
      'Permission denied',
      '${_panel('1', 0, 2400)}\n${_panel('2', 2000, 3000)}',
      '${_panel('1', 1080, 2400)}\n${_panel('2', 1080, 2400)}',
      '$honorFoldableDisplayDump\n${_panel('3', 800, 1200)}',
    ]) {
      expect(
        FoldableDisplayParser.parse(dump, deviceStates: honorFoldableStates),
        isNull,
      );
    }
  });

  test('不完整或旧版缓存不生成伪造的第二块屏幕', () {
    for (final value in [
      null,
      {},
      [],
      {'innerResolution': '2352x2172'},
      {'innerResolution': '-', 'outerResolution': '2420x1080'},
    ]) {
      expect(FoldableDisplayInfo.fromJson(value), isNull);
    }
  });

  test('提取后的显示解析保持原有分辨率、密度与刷新率结果', () {
    expect(
      AndroidDisplayParser.formatResolution('1080x2400', density: '480'),
      '2400x1080 (480dpi)',
    );
    expect(AndroidDisplayParser.formatResolution('-'), '-');
    expect(AndroidDisplayParser.densityQualifier('480'), '3x (xxhdpi)');
    expect(AndroidDisplayParser.densityQualifier('420'), '2.63x (xxhdpi)');
    expect(AndroidDisplayParser.densityQualifier('-'), '-');
    expect(
      AndroidDisplayParser.refreshRate('supportedRefreshRates [60, 120]'),
      '120 Hz',
    );
    expect(AndroidDisplayParser.refreshRate('renderFrameRate 90.0'), '90 Hz');
    expect(
      AndroidDisplayParser.refreshRate('supportedModes [{fps=60.0}]'),
      '60 Hz',
    );
    expect(AndroidDisplayParser.refreshRate(''), '-');
  });
}

/// 为边界用例构建最小物理屏记录，默认名称不暗示内外屏。
String _panel(
  String id,
  int width,
  int height, {
  String name = 'Built-in Screen',
  String extra = '',
}) =>
    '  DisplayDeviceInfo{"$name": uniqueId="local:$id", '
    '$width x $height, $extra type INTERNAL, state ON}';
