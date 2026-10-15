import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/layout_inspector/layout_inspector_service.dart';
import 'package:any_deck/core/layout_inspector/layout_node.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adb_service.dart';

const _harmonyLayoutJson = '''
{
  "attributes": {"bounds": "[0,0][1224,2776]", "type": "Root"},
  "children": [
    {
      "attributes": {
        "bounds": "[12,34][500,260]",
        "type": "Text",
        "id": "title",
        "bundleName": "com.example.demo",
        "description": "标题 & 说明",
        "text": "Hello"
      },
      "children": []
    }
  ]
}
''';

class _FakeHarmonyLayoutHdc extends HdcService {
  _FakeHarmonyLayoutHdc() : super(executable: 'hdc');

  final List<String> commands = [];
  int screenshotCalls = 0;

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(command);
    if (command.startsWith('cat ')) {
      return const AdbResult(
        exitCode: 0,
        stdout: _harmonyLayoutJson,
        stderr: '',
      );
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    screenshotCalls++;
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  test('解析 HarmonyOS dumpLayout JSON 并映射共享属性', () {
    final root = parseHarmonyLayoutJson(_harmonyLayoutJson)!;
    final title = root.children.single;

    expect(root.className, 'Root');
    expect(title.className, 'Text');
    expect(title.resourceId, 'title');
    expect(title.packageName, 'com.example.demo');
    expect(title.contentDesc, '标题 & 说明');
    expect(title.rect, const Rect.fromLTRB(12, 34, 500, 260));
    expect(title.parent, same(root));
  });

  test('HarmonyOS 布局服务执行 dump、读取、清理并生成可导出 XML', () async {
    final hdc = _FakeHarmonyLayoutHdc();
    final service = LayoutInspectorService(
      FakeAdbService(),
      hdc: hdc,
      isHarmonyResolver: (_) => true,
    );

    final (root, xml) = await service.captureLayout('harmony-device');

    expect(root.children.single.resourceId, 'title');
    expect(hdc.commands[0], startsWith('uitest dumpLayout -p '));
    expect(hdc.commands[1], startsWith('cat '));
    expect(hdc.commands[2], startsWith('rm '));
    expect(xml, contains('class="Text"'));
    expect(xml, contains('description="标题 &amp; 说明"'));
  });

  test('HarmonyOS 布局截图走 HDC 而不是 ADB', () async {
    final hdc = _FakeHarmonyLayoutHdc();
    final service = LayoutInspectorService(
      FakeAdbService(),
      hdc: hdc,
      isHarmonyResolver: (_) => true,
    );

    expect(await service.captureScreenshot('harmony-device'), [1, 2, 3]);
    expect(hdc.screenshotCalls, 1);
  });
}
