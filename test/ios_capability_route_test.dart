import 'dart:typed_data';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/device_actions/device_action_service.dart';
import 'package:any_deck/core/ios/ios_app_info.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_layout_service.dart';
import 'package:any_deck/core/layout_inspector/layout_inspector_service.dart';
import 'package:any_deck/core/mcp/models/mcp_tool_definition.dart';
import 'package:any_deck/core/mcp/registry/mcp_tool_registry.dart';
import 'package:any_deck/core/mcp/tools/mcp_ios_tools.dart';
import 'package:any_deck/core/mcp/tools/mcp_ui_tools.dart';
import 'package:flutter_test/flutter_test.dart';

const _wdaSource =
    '<AppiumAUT><XCUIElementTypeWindow x="0" y="0" '
    'width="375" height="667"><XCUIElementTypeButton name="login" '
    'label="登录" x="10" y="20" width="100" height="40"/>'
    '</XCUIElementTypeWindow></AppiumAUT>';

class _IosCommands extends IosCommandService {
  _IosCommands() : super(executable: 'ios');

  String? lastAction;

  @override
  Future<AdbResult> automationGeometry(String udid) async => const AdbResult(
    exitCode: 0,
    stdout: '{"ready":true,"width":375,"height":667}',
    stderr: '',
  );

  @override
  Future<AdbResult> automationSource(String udid) async => AdbResult(
    exitCode: 0,
    stdout: '{"value":${_jsonString(_wdaSource)}}',
    stderr: '',
  );

  @override
  Future<Uint8List> captureScreenshot(String udid) async =>
      Uint8List.fromList([1, 2, 3]);

  @override
  Future<AdbResult> tap(String udid, double x, double y) async {
    lastAction = 'tap:$x:$y';
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<List<IosAppInfo>> listApps(String udid) async => const [
    IosAppInfo(bundleId: 'com.example.app', name: 'Example'),
  ];
}

String _jsonString(String value) => '"${value.replaceAll('"', '\\"')}"';

class _Adb extends Fake implements AdbService {}

class _Actions extends Fake implements DeviceActionService {}

class _Layout extends Fake implements LayoutInspectorService {}

void main() {
  test('WDA UI Tree 使用截图尺寸把 point 映射为像素', () async {
    final service = IosLayoutService(_IosCommands());
    final (root, xml) = await service.capture(
      'ios-1',
      imageWidth: 1125,
      imageHeight: 2001,
    );
    final button = root.children.single.children.single;
    expect(button.className, 'XCUIElementTypeButton');
    expect(button.resourceId, 'login');
    expect(button.bounds, '[30,60][330,180]');
    expect(button.parent, root.children.single);
    expect(xml, contains('bounds="[30,60][330,180]"'));
  });

  test('MCP UI 工具对 iOS 使用 WDA 与 iOS 截图，不调用 ADB', () async {
    final ios = _IosCommands();
    final tools = McpUiTools(
      adbService: _Adb(),
      actionService: _Actions(),
      layoutService: _Layout(),
      iosService: ios,
      isIosDevice: (_) async => true,
    ).getTools();
    Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) =>
        tools.singleWhere((tool) => tool.name == name).handler(args);

    final screenshot = await call('take_screenshot', {'deviceId': 'ios-1'});
    expect(screenshot['coordinateSpace'], 'ios_points');
    expect(screenshot['byteLength'], 3);
    final tree = await call('inspect_ui_layout', {'deviceId': 'ios-1'});
    expect(tree['xml'], contains('XCUIElementTypeButton'));
    await call('device_input_tap', {
      'deviceId': 'ios-1',
      'x': 10.5,
      'y': 20.25,
    });
    expect(ios.lastAction, 'tap:10.5:20.25');
  });

  test('MCP 拒绝对 iOS 执行仅支持 ADB 的工具', () async {
    final registry = McpToolRegistry()..isIosDevice = (_) async => true;
    registry.register(
      McpToolDefinition(
        name: 'execute_shell',
        description: 'ADB shell',
        inputSchema: const {},
        handler: (_) async => {'unexpected': true},
      ),
    );
    await expectLater(
      registry.executeTool(
        name: 'execute_shell',
        arguments: {'deviceId': 'ios-1'},
      ),
      throwsUnsupportedError,
    );
  });

  test('iOS MCP App 工具列出 Bundle ID', () async {
    final tools = McpIosTools(
      commands: _IosCommands(),
      isIosDevice: (_) async => true,
    ).getTools();
    final result = await tools
        .singleWhere((tool) => tool.name == 'ios_list_apps')
        .handler({'deviceId': 'ios-1'});
    expect(result['count'], 1);
    expect((result['apps'] as List).single['bundleId'], 'com.example.app');
  });
}
