import 'dart:convert';

import 'ios_app_info.dart';
import 'ios_command_service.dart';
import 'ios_process_info.dart';
import 'ios_process_parser.dart';
import 'ios_process_session.dart';

/// 单设备进程数据源：全进程查询与低频应用元数据缓存分离。
class IosProcessService {
  IosProcessService(IosCommandService commands, this.udid)
    : session = IosProcessSession(commands);

  final String udid;
  final IosProcessSession session;
  List<IosAppInfo> _apps = const [];
  DateTime? _appsAttempt;
  bool _closed = false;
  String? metadataError;

  void close() {
    _closed = true;
    session.close();
  }

  Future<List<IosProcessInfo>> read({bool refreshApps = false}) async {
    final processes = await _readProcesses();
    final now = DateTime.now();
    if (refreshApps ||
        _appsAttempt == null ||
        now.difference(_appsAttempt!) >= const Duration(minutes: 5)) {
      _appsAttempt = now;
      try {
        final result = await session.run(['apps', '--all', '--udid=$udid']);
        if (!result.isSuccess) throw StateError(result.message);
        _requirePayload(result.stdout);
        _apps = IosCommandService.parseApps(result.stdout);
        metadataError = null;
      } catch (error) {
        // 元数据失败保留旧缓存，并让页面提示分类信息可能不完整。
        metadataError = error.toString();
      }
    }
    return IosProcessParser.associate(processes, _apps);
  }

  Future<List<IosProcessInfo>> _readProcesses() async {
    final result = await session.run(['ps', '--udid=$udid']);
    if (!result.isSuccess) throw StateError(result.message);
    _requirePayload(result.stdout);
    return IosProcessParser.parse(result.stdout);
  }

  /// 结束前回读 PID 身份，阻止已退出或 PID 重用后的误操作。
  Future<void> kill(IosProcessInfo expected) async {
    final current = await _readProcesses();
    final same = current.any(
      (item) =>
          item.pid == expected.pid &&
          item.name == expected.name &&
          item.executablePath == expected.executablePath &&
          item.startedAt == expected.startedAt,
    );
    if (!same) throw const IosProcessChanged();
    if (_closed) throw StateError('iOS process session closed');
    final result = await session.run([
      'kill',
      '--pid=${expected.pid}',
      '--udid=$udid',
    ]);
    if (!result.isSuccess) throw StateError(result.message);
  }

  /// 空数组是有效快照；仅日志或损坏输出不能覆盖上一次可用数据。
  static void _requirePayload(String output) {
    bool payload(Object? value) =>
        value is List || (value is Map && !value.containsKey('level'));
    try {
      if (payload(jsonDecode(output))) return;
    } catch (_) {}
    for (final line in const LineSplitter().convert(output)) {
      try {
        if (payload(jsonDecode(line))) return;
      } catch (_) {}
    }
    throw const FormatException('go-ios returned no JSON payload');
  }
}

/// 确认期间进程已退出或身份改变，由 UI 转换为本地化提示。
class IosProcessChanged implements Exception {
  const IosProcessChanged();
}
