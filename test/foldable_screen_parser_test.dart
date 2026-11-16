import 'package:any_deck/core/foldable/foldable_screen_models.dart';
import 'package:any_deck/core/foldable/foldable_screen_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/foldable_screen_fixtures.dart';

/// 验证运行时双向布局证据，避免把双屏枚举或固定姿态编号当作能力。
void main() {
  test('Samsung 自动模式识别内屏与双向普通姿态映射', () {
    final snapshot = _parse();
    expect(snapshot, isNotNull);
    expect(snapshot!.capability.innerStateId, 3);
    expect(snapshot.capability.outerStateId, 0);
    expect(snapshot.capability.innerPhysicalId, '4630947004648141459');
    expect(snapshot.capability.outerPhysicalId, '4630947123231501204');
    expect(snapshot.currentScreen, FoldableScreen.inner);
    expect(snapshot.committedStateId, 3);
    expect(snapshot.hasOverride, isFalse);
    expect(snapshot.overrideStateId, isNull);
  });

  test('手动外屏按 committed 布局读取 logical display 0 的新物理屏', () {
    final stateDump = foldableScreenStateDump
        .replaceFirst(
          "identifier=3, name='OPENED'",
          "identifier=0, name='CLOSED'",
        )
        .replaceFirst(
          'mOverrideState=Optional.empty',
          "mOverrideState=Optional[DeviceState{identifier=0, name='CLOSED'}]",
        );
    final snapshot = _parse(stateDump: stateDump)!;
    expect(snapshot.currentScreen, FoldableScreen.outer);
    expect(snapshot.committedStateId, 0);
    expect(snapshot.hasOverride, isTrue);
    expect(snapshot.overrideStateId, 0);
  });

  test('识别其他工具创建的特殊姿态覆盖并保留其编号', () {
    final snapshot = _parse(
      stateDump: foldableScreenStateDump.replaceFirst(
        'mOverrideState=Optional.empty',
        "mOverrideState=Optional[DeviceState{identifier=5, name='CONCURRENT_OUTER_DEFAULT'}]",
      ),
    )!;
    expect(snapshot.currentScreen, FoldableScreen.inner);
    expect(snapshot.hasOverride, isTrue);
    expect(snapshot.overrideStateId, 5);
  });

  test('短状态输出缺少 Override 行代表自动模式', () {
    final snapshot = _parse(
      stateDump: "Committed state: DeviceState{identifier=3, name='OPENED'}\n",
    )!;
    expect(snapshot.currentScreen, FoldableScreen.inner);
    expect(snapshot.hasOverride, isFalse);
    expect(snapshot.overrideStateId, isNull);
  });

  test('短状态输出正确读取 Override 行', () {
    final snapshot = _parse(
      stateDump:
          "Committed state: DeviceState{identifier=0, name='CLOSED'}\n"
          "Base state: DeviceState{identifier=3, name='OPENED'}\n"
          "Override state: DeviceState{identifier=0, name='CLOSED'}\n",
    )!;
    expect(snapshot.currentScreen, FoldableScreen.outer);
    expect(snapshot.hasOverride, isTrue);
    expect(snapshot.overrideStateId, 0);
  });

  test('其他厂商普通状态编号与前缀变化不影响角色', () {
    String renumber(String input) => input
        .replaceAll('identifier=0', 'identifier=14')
        .replaceAll('identifier=3', 'identifier=27')
        .replaceAll('state(0)', 'state(14)')
        .replaceAll('state(3)', 'state(27)')
        .replaceAll("name='CLOSED'", "name='STATE_FOLDED'")
        .replaceAll("name='OPENED'", "name='STATE_FLAT'");
    final snapshot = _parse(
      states: renumber(foldableScreenStates),
      stateDump: renumber(foldableScreenStateDump),
      displayDump: renumber(foldableScreenDisplayDump),
    )!;
    expect(snapshot.capability.innerStateId, 27);
    expect(snapshot.capability.outerStateId, 14);
    expect(snapshot.currentScreen, FoldableScreen.inner);
  });

  test('支持 CLOSE 和 OPEN 普通名称但不依赖它们猜测物理编号', () {
    final snapshot = _parse(
      states: foldableScreenStates
          .replaceAll("name='CLOSED'", "name='CLOSE'")
          .replaceAll("name='OPENED'", "name='OPEN'"),
    );
    expect(snapshot?.capability.outerStateId, 0);
  });

  test('CRLF、物理屏枚举倒序和重复快照不改变能力', () {
    final lines = foldableScreenDisplayDump.split('\n');
    final firstPanel = lines[1];
    lines[1] = lines[2];
    lines[2] = firstPanel;
    lines.insert(3, firstPanel);
    expect(
      _parse(displayDump: lines.join('\r\n'))?.currentScreen,
      FoldableScreen.inner,
    );
  });

  test('已知特殊当前姿态仍按主屏布局显示但不成为切换目标', () {
    final snapshot = _parse(
      stateDump: foldableScreenStateDump.replaceFirst(
        "identifier=3, name='OPENED'",
        "identifier=5, name='CONCURRENT_OUTER_DEFAULT'",
      ),
    )!;
    expect(snapshot.currentScreen, FoldableScreen.outer);
    expect(snapshot.capability.innerStateId, 3);
    expect(snapshot.capability.outerStateId, 0);
  });

  test('没有当前姿态布局时不伪造当前屏幕', () {
    final dump = foldableScreenDisplayDump
        .split('\n')
        .where((line) => !line.contains('state(2):'))
        .join('\n');
    final snapshot = _parse(
      stateDump: foldableScreenStateDump.replaceFirst(
        "identifier=3, name='OPENED'",
        "identifier=2, name='HALF_OPENED'",
      ),
      displayDump: dump,
    )!;
    expect(snapshot.currentScreen, isNull);
  });

  test('特殊当前姿态主屏未启用时不伪造当前屏幕', () {
    final lines = foldableScreenDisplayDump.split('\n');
    final index = lines.indexWhere((line) => line.contains('state(2):'));
    lines[index] = lines[index].replaceFirst('dispId: 0(ON)', 'dispId: 0(OFF)');
    final snapshot = _parse(
      stateDump: foldableScreenStateDump.replaceFirst(
        "identifier=3, name='OPENED'",
        "identifier=2, name='HALF_OPENED'",
      ),
      displayDump: lines.join('\n'),
    )!;
    expect(snapshot.currentScreen, isNull);
  });

  test('只枚举两个物理屏和普通名称没有布局证据时隐藏能力', () {
    expect(
      _parse(
        displayDump: foldableScreenDisplayDump
            .split('DeviceStateToLayoutMap:')
            .first,
      ),
      isNull,
    );
  });

  test('外接屏、虚拟屏和重复单物理屏不能组成双屏能力', () {
    for (final dump in [
      foldableScreenDisplayDump.replaceFirst('type INTERNAL', 'type EXTERNAL'),
      foldableScreenDisplayDump.replaceFirst('type INTERNAL', 'type VIRTUAL'),
      foldableScreenDisplayDump.replaceAll(
        'local:4630947123231501204',
        'local:4630947004648141459',
      ),
    ]) {
      expect(_parse(displayDump: dump), isNull);
    }
  });

  test('三块内置物理屏及无效尺寸不开放二态切换', () {
    for (final dump in [
      '$foldableScreenDisplayDump\n'
          '  DisplayDeviceInfo{"Extra": uniqueId="local:99", 1080 x 1920, type INTERNAL, state OFF}',
      foldableScreenDisplayDump.replaceFirst('2448 x 1848', '0 x 1848'),
    ]) {
      expect(_parse(displayDump: dump), isNull);
    }
  });

  test('两种普通姿态映射到相同主屏不开放能力', () {
    final lines = foldableScreenDisplayDump.split('\n');
    final outerIndex = lines.indexWhere((line) => line.contains('state(0):'));
    final innerLine = lines.firstWhere((line) => line.contains('state(3):'));
    lines[outerIndex] = innerLine.replaceFirst('state(3):', 'state(0):');
    expect(_parse(displayDump: lines.join('\n')), isNull);
  });

  test('只提供 TENT、HALF、REAR、CONCURRENT 不作为普通目标', () {
    for (final replacement in [
      "name='HALF_OPENED'",
      "name='REAR_OPENED'",
      "name='CONCURRENT_INNER_DEFAULT'",
      "name='TENT'",
    ]) {
      expect(
        _parse(
          states: foldableScreenStates.replaceAll("name='OPENED'", replacement),
        ),
        isNull,
      );
    }
  });

  test('普通姿态的双屏同时启用或主屏关闭均不作为切换目标', () {
    for (final replacement in ['dispId: 1(ON)', 'dispId: 1(OFF)']) {
      final lines = foldableScreenDisplayDump.split('\n');
      final index = lines.indexWhere((line) => line.contains('state(3):'));
      lines[index] = replacement == 'dispId: 1(ON)'
          ? lines[index].replaceFirst('dispId: 1(OFF)', replacement)
          : lines[index].replaceFirst('dispId: 0(ON)', 'dispId: 0(OFF)');
      expect(_parse(displayDump: lines.join('\n')), isNull);
    }
  });

  test('明确的 Inner 或 Cover 命名与状态布局相矛盾时拒绝', () {
    expect(
      _parse(
        displayDump: foldableScreenDisplayDump.replaceFirst(
          'DisplayDeviceInfo{"内置屏幕"',
          'DisplayDeviceInfo{"Cover Screen"',
        ),
      ),
      isNull,
    );
  });

  test('缺失状态、未知格式或不完整覆盖信息均保守拒绝', () {
    for (final stateDump in [
      '',
      'Unknown command',
      'mCommittedState=Optional.empty\nmOverrideState=Optional.empty',
      "mCommittedState=Optional[DeviceState{identifier=3, name='OPENED'}]",
      foldableScreenStateDump.replaceAll('Optional.empty', 'Optional[unknown]'),
      foldableScreenStateDump.replaceFirst('identifier=3', 'identifier=99'),
    ]) {
      expect(_parse(stateDump: stateDump), isNull);
    }
    expect(_parse(states: ''), isNull);
    expect(_parse(displayDump: 'unknown format'), isNull);
  });

  test('布局含未知物理地址或重复逻辑 ID 时拒绝', () {
    expect(
      _parse(
        displayDump: foldableScreenDisplayDump.replaceAll(
          'StablePhysical{id=4630947004648141459',
          'StablePhysical{id=999',
        ),
      ),
      isNull,
    );
    expect(
      _parse(
        displayDump: foldableScreenDisplayDump.replaceAll(
          'dispId: 1(OFF)',
          'dispId: 0(OFF)',
        ),
      ),
      isNull,
    );
  });

  test('部分布局地址格式未知或未知内置物理屏不继续猜测', () {
    expect(
      _parse(
        displayDump: foldableScreenDisplayDump.replaceFirst(
          'addr: StablePhysical{id=4630947123231501204, port=148}',
          'addr: UnknownPhysical{id=4630947123231501204}',
        ),
      ),
      isNull,
    );
    expect(
      _parse(
        displayDump:
            '$foldableScreenDisplayDump\n'
            '  DisplayDeviceInfo{"Unknown": uniqueId="custom:99", 1080 x 1920, type INTERNAL, state OFF}',
      ),
      isNull,
    );
  });
}

/// 为用例复用相同证据入口，避免各测试遗漏必要的系统快照。
FoldableScreenSnapshot? _parse({
  String states = foldableScreenStates,
  String stateDump = foldableScreenStateDump,
  String displayDump = foldableScreenDisplayDump,
}) => FoldableScreenParser.parse(
  states: states,
  stateDump: stateDump,
  displayDump: displayDump,
);
