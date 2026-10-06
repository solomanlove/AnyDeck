import 'dart:convert';

import 'ios_app_info.dart';
import 'ios_process_info.dart';

/// 解析 go-ios 进程结构，并用设备安装路径关联应用，避免同名 Runner 误匹配。
class IosProcessParser {
  static List<IosProcessInfo> parse(String output) {
    final processes = <int, IosProcessInfo>{};

    void collect(Object? value, [String? key]) {
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      if (value is! Map || value.containsKey('level')) return;
      final pid = _pid(
        value['pid'] ??
            value['Pid'] ??
            value['PID'] ??
            value['ProcessIdentifier'] ??
            key,
      );
      if (pid != null) {
        final path = _text(value, [
          'RealAppName',
          'realAppName',
          'executablePath',
        ]);
        final bundleId = _text(value, [
          'bundleIdentifier',
          'BundleIdentifier',
          'CFBundleIdentifier',
          'bundleId',
        ]);
        processes[pid] = IosProcessInfo(
          pid: pid,
          name:
              _text(value, [
                'Name',
                'name',
                'processName',
                'ExecutableName',
                'value',
              ]) ??
              bundleId ??
              path?.split('/').last ??
              'PID $pid',
          executablePath: path,
          bundleId: bundleId,
          startedAt: _startDate(
            _text(value, ['StartDate', 'startDate']) ?? '',
          ),
          isApplication: switch (value['IsApplication'] ??
              value['isApplication']) {
            bool flag => flag,
            _ => null,
          },
        );
        // 记录内部元数据不应再被误识别为其它进程。
        return;
      }
      final hasChildren = value.values.any(
        (item) => item is Map || item is List,
      );
      for (final entry in value.entries) {
        // 包装对象中的 count 等数字不是进程；仅叶子名称映射接受数字 PID。
        final mappedPid = hasChildren ? null : _pid(entry.value);
        if (mappedPid != null) {
          processes[mappedPid] = IosProcessInfo(
            pid: mappedPid,
            name: '${entry.key}',
          );
        } else {
          collect(entry.value, '${entry.key}');
        }
      }
    }

    // 同时兼容纯 JSON、格式化 JSON 及前置 WARN 的逐行 JSON。
    try {
      collect(jsonDecode(output));
    } catch (_) {
      for (final line in const LineSplitter().convert(output)) {
        try {
          collect(jsonDecode(line));
        } catch (_) {}
      }
    }
    return processes.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// 每次刷新只建立一份索引；App Extension 通过最外层 .app 目录定位宿主。
  static List<IosProcessInfo> associate(
    List<IosProcessInfo> processes,
    List<IosAppInfo> apps,
  ) {
    final byPath = <String, IosAppInfo?>{};
    final byBundle = <String, IosAppInfo>{};
    for (final app in apps) {
      byBundle[app.bundleId] = app;
      final path = app.path;
      if (path == null || path.isEmpty) continue;
      final canonical = _canonicalPath(path);
      // 不明确的重复路径不猜测归属。
      byPath[canonical] = byPath.containsKey(canonical) ? null : app;
    }
    return processes.map((process) {
      final path = process.executablePath;
      final canonical = path == null ? null : _canonicalPath(path);
      final appEnd = canonical?.indexOf('.app/');
      final app = canonical != null && appEnd != null && appEnd >= 0
          ? byPath[canonical.substring(0, appEnd + 4)]
          : null;
      return process.withApp(
        app ?? (process.isExtension ? null : byBundle[process.bundleId]),
      );
    }).toList();
  }

  /// iOS 的 /var 与 /private/var 为同一路径；不按目录名或进程名模糊关联。
  static String _canonicalPath(String value) {
    final normalized = Uri.file(value, windows: false)
        .normalizePath()
        .toFilePath(windows: false)
        .replaceFirst(RegExp(r'/+$'), '');
    return normalized.startsWith('/private/var/')
        ? normalized.substring('/private'.length)
        : normalized;
  }

  /// Go time.Time 的零值不是设备真实启动时间。
  static DateTime? _startDate(String value) {
    final date = DateTime.tryParse(value);
    return date != null && date.year > 1 ? date : null;
  }

  static int? _pid(Object? value) {
    final pid = value is int
        ? value
        : value is String
        ? int.tryParse(value)
        : null;
    return pid != null && pid > 0 ? pid : null;
  }

  static String? _text(Map value, List<String> keys) {
    for (final key in keys) {
      final text = value[key];
      if (text is String && text.trim().isNotEmpty) return text.trim();
    }
    return null;
  }
}
