import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../ios/ios_command_service.dart';
import '../models/mcp_tool_definition.dart';

/// iOS 状态、坐标、进程与有界日志采样；WDA 不可用时明确失败。
class McpIosDiagnosticTools {
  McpIosDiagnosticTools(this.commands);
  final IosCommandService commands;

  List<McpToolDefinition> getTools() => [
    _tool('ios_get_automation_status', '查询指定 UDID 的 WDA 状态，不会自动安装或启动 WDA', (
      args,
    ) async {
      final r = await commands.automationStatus(args['deviceId'] as String);
      if (!r.isSuccess) throw StateError(r.message);
      return commands.parseAutomationValue(r.stdout);
    }),
    _tool(
      'ios_get_screen_geometry',
      '读取 WDA point 尺寸。截图像素坐标必须按截图宽高与此尺寸换算后再点击；横竖屏变化后重新读取',
      (args) async {
        final r = await commands.automationGeometry(args['deviceId'] as String);
        if (!r.isSuccess) throw StateError(r.message);
        return {
          ...commands.parseAutomationValue(r.stdout),
          'coordinateSpace': 'ios_points',
        };
      },
    ),
    _tool('ios_list_processes', '读取 go-ios 可见的进程及 Bundle ID；未返回的 CPU/内存指标为未知', (
      args,
    ) async {
      final processes = await commands.listProcesses(
        args['deviceId'] as String,
      );
      return {
        'deviceId': args['deviceId'],
        'processes': processes
            .take(500)
            .map((p) => {'pid': p.pid, 'name': p.name, 'bundleId': p.bundleId})
            .toList(),
        'truncated': processes.length > 500,
      };
    }),
    _tool(
      'ios_query_syslog',
      '采样接下来最多 3 秒的 iOS syslog，最多返回 500 行；不代表历史日志或完整崩溃报告',
      _logs,
      extra: {
        'keyword': {'type': 'string'},
        'limitLines': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 500,
          'default': 100,
        },
      },
    ),
  ];

  McpToolDefinition _tool(
    String name,
    String description,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler, {
    Map<String, dynamic> extra = const {},
  }) => McpToolDefinition(
    name: name,
    category: name.contains('syslog') ? 'log' : 'device',
    platforms: const {'ios'},
    readOnly: true,
    description: description,
    inputSchema: {
      'type': 'object',
      'required': ['deviceId'],
      'properties': {
        'deviceId': {
          'type': 'string',
          'description': 'list_devices 返回的在线 iOS UDID',
        },
        ...extra,
      },
    },
    handler: handler,
  );

  Future<Map<String, dynamic>> _logs(Map<String, dynamic> args) async {
    final process = await commands.startSyslog(args['deviceId'] as String);
    final lines = <String>[];
    final limit = args['limitLines'] as int? ?? 100;
    final ready = Completer<void>();
    final errors = StringBuffer();
    final stderr = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((v) {
          if (errors.length < 8192) {
            errors.write(
              v.substring(0, v.length.clamp(0, 8192 - errors.length)),
            );
          }
        });
    var received = 0;
    var pending = '';
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (chunk) {
            received += chunk.length;
            if (received > 256 * 1024) {
              if (!ready.isCompleted) ready.complete();
              return;
            }
            pending += chunk;
            final parts = pending.split('\n');
            pending = parts.removeLast();
            for (final line in parts) {
              if (line.contains(args['keyword'] as String? ?? '') &&
                  lines.length < limit) {
                lines.add(line);
              }
            }
            if (lines.length >= limit && !ready.isCompleted) ready.complete();
          },
          onDone: () {
            if (!ready.isCompleted) ready.complete();
          },
        );
    try {
      await ready.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    } finally {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return 124;
        },
      );
      await stdout.cancel();
      await stderr.cancel();
    }
    if (lines.isEmpty && errors.isNotEmpty) throw StateError(errors.toString());
    return {
      'deviceId': args['deviceId'],
      'logs': lines,
      'sampleSeconds': 3,
      'truncated': lines.length >= limit || received > 256 * 1024,
      'source': 'syslog',
    };
  }
}
