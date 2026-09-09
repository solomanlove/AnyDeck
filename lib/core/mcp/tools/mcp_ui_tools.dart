import 'dart:convert';

import '../../adb/adb_service.dart';
import '../../device_actions/device_action_service.dart';
import '../../layout_inspector/layout_inspector_service.dart';
import '../../layout_inspector/layout_node.dart';
import '../models/mcp_tool_definition.dart';

/// 屏幕截屏与 UI 自动化交互相关的 MCP Tools
class McpUiTools {
  final AdbService adbService;
  final DeviceActionService actionService;
  final LayoutInspectorService layoutService;

  McpUiTools({
    required this.adbService,
    required this.actionService,
    required this.layoutService,
  });

  /// 获取所有 UI 与交互工具
  List<McpToolDefinition> getTools() {
    return [
      _buildTakeScreenshotTool(),
      _buildInspectUiLayoutTool(),
      _buildInputTapTool(),
      _buildInputSwipeTool(),
      _buildInputTextTool(),
      _buildPressKeyTool(),
    ];
  }

  /// 1. 截取屏幕图像并返回 Base64 编码 (供多模态 Vision 模型理解)
  McpToolDefinition _buildTakeScreenshotTool() {
    return McpToolDefinition(
      name: 'take_screenshot',
      category: 'ui',
      description: '截取设备当前屏幕图像，返回 Base64 格式的 PNG/JPEG 图片数据供多模态大模型进行视觉分析',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId'],
        'properties': {
          'deviceId': {
            'type': 'string',
            'description': '目标设备序列号',
          },
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String?;
        if (deviceId == null || deviceId.isEmpty) {
          throw ArgumentError('必须提供 deviceId');
        }

        final bytes = await layoutService.captureScreenshot(deviceId);
        final base64Image = base64Encode(bytes);

        return {
          'deviceId': deviceId,
          'mimeType': 'image/png',
          'byteLength': bytes.lengthInBytes,
          'base64': base64Image,
          'summary': '截屏成功，生成 ${bytes.lengthInBytes} 字节图像数据',
        };
      },
    );
  }

  /// 递归计算 LayoutNode 节点数量
  int _countNodes(LayoutNode node) {
    var count = 1;
    for (final child in node.children) {
      count += _countNodes(child);
    }
    return count;
  }

  /// 2. Dump UI 控件树结构 (Hierarchy XML / 控件节点)
  McpToolDefinition _buildInspectUiLayoutTool() {
    return McpToolDefinition(
      name: 'inspect_ui_layout',
      category: 'ui',
      description: '抓取当前界面 UI 控件树 XML 层次结构，便于 AI 理解当前界面的按钮、输入框、文本节点及其屏幕坐标(bounds)',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId'],
        'properties': {
          'deviceId': {
            'type': 'string',
            'description': '目标设备序列号',
          },
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String?;
        if (deviceId == null || deviceId.isEmpty) {
          throw ArgumentError('必须提供 deviceId');
        }

        final (rootNode, rawXml) = await layoutService.captureLayout(deviceId);
        final totalCount = _countNodes(rootNode);

        return {
          'deviceId': deviceId,
          'nodeCount': totalCount,
          'xml': rawXml,
          'summary': '已成功抓取 UI 控件树，共包含 $totalCount 个控件节点',
        };
      },
    );
  }

  /// 3. 点击屏幕指定像素坐标
  McpToolDefinition _buildInputTapTool() {
    return McpToolDefinition(
      name: 'device_input_tap',
      category: 'ui',
      description: '在设备屏幕的指定 (x, y) 坐标处模拟手指点击操作',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'x', 'y'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'x': {'type': 'integer', 'description': 'X 轴绝对像素坐标'},
          'y': {'type': 'integer', 'description': 'Y 轴绝对像素坐标'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final x = (args['x'] as num).toInt();
        final y = (args['y'] as num).toInt();

        final result = await actionService.tap(deviceId, x, y);
        if (!result.isSuccess) {
          throw Exception('点击失败: ${result.stderr}');
        }
        return {
          'deviceId': deviceId,
          'x': x,
          'y': y,
          'success': true,
          'summary': '已在坐标 ($x, $y) 模拟点击',
        };
      },
    );
  }

  /// 4. 滑动屏幕手势
  McpToolDefinition _buildInputSwipeTool() {
    return McpToolDefinition(
      name: 'device_input_swipe',
      category: 'ui',
      description: '在设备屏幕上从起点坐标 (x1, y1) 滑动到终点坐标 (x2, y2)',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'x1', 'y1', 'x2', 'y2'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'x1': {'type': 'integer', 'description': '起点 X 坐标'},
          'y1': {'type': 'integer', 'description': '起点 Y 坐标'},
          'x2': {'type': 'integer', 'description': '终点 X 坐标'},
          'y2': {'type': 'integer', 'description': '终点 Y 坐标'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final x1 = (args['x1'] as num).toInt();
        final y1 = (args['y1'] as num).toInt();
        final x2 = (args['x2'] as num).toInt();
        final y2 = (args['y2'] as num).toInt();

        final result = await actionService.swipe(
          deviceId,
          x1,
          y1,
          x2,
          y2,
        );
        if (!result.isSuccess) {
          throw Exception('滑动失败: ${result.stderr}');
        }
        return {
          'deviceId': deviceId,
          'from': {'x': x1, 'y': y1},
          'to': {'x': x2, 'y': y2},
          'success': true,
          'summary': '已执行从 ($x1, $y1) 到 ($x2, $y2) 的滑动手势',
        };
      },
    );
  }

  /// 5. 输入文本字符
  McpToolDefinition _buildInputTextTool() {
    return McpToolDefinition(
      name: 'device_input_text',
      category: 'ui',
      description: '向设备当前获得焦点的输入框键入文本内容（支持空格自动转义）',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'text'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'text': {'type': 'string', 'description': '要输入的文本内容'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final text = args['text'] as String;

        final result = await actionService.inputText(deviceId, text);
        if (!result.isSuccess) {
          throw Exception('输入文本失败: ${result.stderr}');
        }
        return {
          'deviceId': deviceId,
          'text': text,
          'success': true,
          'summary': '已成功输入文本: "$text"',
        };
      },
    );
  }

  /// 6. 模拟硬件按键
  McpToolDefinition _buildPressKeyTool() {
    return McpToolDefinition(
      name: 'device_press_key',
      category: 'ui',
      description: '向设备发送 Android KeyCode 按键事件 (如 3=Home, 4=Back, 24=VolumeUp, 25=VolumeDown, 26=Power, 66=Enter)',
      inputSchema: {
        'type': 'object',
        'required': ['deviceId', 'keyCode'],
        'properties': {
          'deviceId': {'type': 'string', 'description': '目标设备序列号'},
          'keyCode': {'type': 'integer', 'description': 'Android KeyCode 整数值'},
        },
      },
      handler: (args) async {
        final deviceId = args['deviceId'] as String;
        final keyCode = (args['keyCode'] as num).toInt();

        final result = await actionService.keyEvent(deviceId, keyCode);
        if (!result.isSuccess) {
          throw Exception('按键事件发送失败: ${result.stderr}');
        }
        return {
          'deviceId': deviceId,
          'keyCode': keyCode,
          'success': true,
          'summary': '已发送 KeyCode: $keyCode',
        };
      },
    );
  }
}
