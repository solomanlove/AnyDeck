import 'dart:convert';

/// 手机端导出的系统日统计快照；保留日桶真实边界，不换算成精确自然日。
class UsageSnapshot {
  UsageSnapshot._(this.json, this.apps);

  final Map<String, dynamic> json;
  final List<AppUsageRecord> apps;

  String get installationId => json['installationId'] as String;
  int get androidUserId => json['androidUserId'] as int;
  int get generatedAtMs => json['generatedAtMs'] as int;
  int get requestedStartMs => json['requestedStartMs'] as int;
  int get rangeStartMs => json['rangeStartMs'] as int;
  int get rangeEndMs => json['rangeEndMs'] as int;
  int get utcOffsetMinutes => json['utcOffsetMinutes'] as int;
  String get timeZone => json['timeZone'] as String;
  int? get screenInteractiveMs => json['screenInteractiveMs'] as int?;
  int? get screenRangeStartMs => json['screenRangeStartMs'] as int?;
  int? get screenRangeEndMs => json['screenRangeEndMs'] as int?;
  int get combinedForegroundMs =>
      apps.fold(0, (sum, app) => sum + app.foregroundMs);

  /// ADB content call 使用 Base64 包装 JSON，避免 Bundle 格式与包名混淆。
  factory UsageSnapshot.fromAdbOutput(String output) {
    if (output.length > 2 * 1024 * 1024) {
      throw const UsageSyncException('usageInvalidResponse');
    }
    final match = RegExp(
      r'\bpayload=([A-Za-z0-9+/]+={0,2})',
    ).firstMatch(output);
    if (match == null) throw const UsageSyncException('usageInvalidResponse');
    try {
      return UsageSnapshot.fromJson(
        jsonDecode(utf8.decode(base64Decode(match.group(1)!)))
            as Map<String, dynamic>,
      );
    } on UsageSyncException {
      rethrow;
    } catch (_) {
      throw const UsageSyncException('usageInvalidResponse');
    }
  }

  factory UsageSnapshot.fromJson(Map<String, dynamic> json) {
    const statuses = {
      'sharing_disabled': 'usageSharingDisabled',
      'permission_required': 'usagePermissionRequired',
      'user_locked': 'usageUserLocked',
      'no_data': 'usageNoData',
      'internal_error': 'usageReadFailed',
    };
    if (json['status'] != 'ok') {
      throw UsageSyncException(
        statuses[json['status']] ?? 'usageInvalidResponse',
      );
    }
    try {
      if (json['schemaVersion'] != 1 ||
          (json['installationId'] as String).isEmpty ||
          (json['timeZone'] as String).isEmpty) {
        throw const FormatException();
      }
      for (final key in [
        'androidUserId',
        'generatedAtMs',
        'requestedStartMs',
        'rangeStartMs',
        'rangeEndMs',
      ]) {
        if (json[key] is! int || (json[key] as int) < 0) {
          throw const FormatException();
        }
      }
      if ((json['rangeStartMs'] as int) > (json['rangeEndMs'] as int) ||
          (json['requestedStartMs'] as int) > (json['generatedAtMs'] as int) ||
          json['utcOffsetMinutes'] is! int ||
          (json['utcOffsetMinutes'] as int).abs() > 14 * 60) {
        throw const FormatException();
      }
      if (json['screenInteractiveMs'] != null) {
        for (final key in [
          'screenInteractiveMs',
          'screenRangeStartMs',
          'screenRangeEndMs',
        ]) {
          if (json[key] is! int || (json[key] as int) < 0) {
            throw const FormatException();
          }
        }
        if ((json['screenRangeStartMs'] as int) >
            (json['screenRangeEndMs'] as int)) {
          throw const FormatException();
        }
      }
      final rows = json['apps'] as List;
      if (rows.length > 5000) throw const FormatException();
      final apps = rows
          .map((row) => AppUsageRecord.fromJson(row as Map<String, dynamic>))
          .toList();
      if (apps.map((app) => app.packageName).toSet().length != apps.length) {
        throw const FormatException();
      }
      apps.sort((a, b) => b.foregroundMs.compareTo(a.foregroundMs));
      return UsageSnapshot._(Map.unmodifiable(json), List.unmodifiable(apps));
    } catch (_) {
      throw const UsageSyncException('usageInvalidResponse');
    }
  }
}

/// 仅含统计事实，名称和图标继续使用 AdbPackage 的现有缓存。
class AppUsageRecord {
  const AppUsageRecord({
    required this.packageName,
    required this.foregroundMs,
    required this.rangeStartMs,
    required this.rangeEndMs,
  });

  final String packageName;
  final int foregroundMs;
  final int rangeStartMs;
  final int rangeEndMs;

  factory AppUsageRecord.fromJson(Map<String, dynamic> json) {
    final name = json['packageName'] as String;
    final duration = json['foregroundMs'] as int;
    final start = json['rangeStartMs'] as int;
    final end = json['rangeEndMs'] as int;
    if (name.isEmpty || duration < 0 || start < 0 || end < start) {
      throw const FormatException();
    }
    return AppUsageRecord(
      packageName: name,
      foregroundMs: duration,
      rangeStartMs: start,
      rangeEndMs: end,
    );
  }
}

/// 错误使用本地化 key；不将使用数据作为异常写入日志。
class UsageSyncException implements Exception {
  const UsageSyncException(this.messageKey);
  final String messageKey;
  @override
  String toString() => messageKey;
}
