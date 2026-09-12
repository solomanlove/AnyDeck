import 'dart:convert';

import 'usage_snapshot.dart';

/// 按安装实例与 Android 用户隔离，ADB 路由变化不会复制同一份记录。
class CompanionSource {
  const CompanionSource(this.installationId, this.androidUserId);
  final String installationId;
  final int androidUserId;
  factory CompanionSource.fromJson(Map<String, dynamic> json) {
    final id = json['installationId'];
    final user = json['androidUserId'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 128 ||
        user is! int ||
        user < 0) {
      throw const UsageSyncException('usageInvalidResponse');
    }
    return CompanionSource(id, user);
  }
  bool matches(CompanionSource other) =>
      installationId == other.installationId &&
      androidUserId == other.androidUserId;
}

/// 分页包复用既有 Base64 外壳；每次解析均检查状态、顺序与来源身份。
Map<String, dynamic> decodeCompanionPayload(String output) {
  try {
    if (output.length > 2 * 1024 * 1024) throw const FormatException();
    final match = RegExp(
      r'\bpayload=([A-Za-z0-9+/]+={0,2})',
    ).firstMatch(output);
    final json =
        jsonDecode(utf8.decode(base64Decode(match!.group(1)!)))
            as Map<String, dynamic>;
    if (json['status'] == 'cursor_invalid') {
      throw const UsageSyncException('historyCursorInvalid');
    }
    if (json['status'] != 'ok') UsageSnapshot.fromJson(json);
    return json;
  } on UsageSyncException {
    rethrow;
  } catch (_) {
    throw const UsageSyncException('usageInvalidResponse');
  }
}

class CompanionPage {
  CompanionPage._(this.json, this.source, this.records);
  final Map<String, dynamic> json;
  final CompanionSource source;
  final List<Map<String, dynamic>> records;
  String get kind => json['kind'] as String;
  int get after => json['after'] as int;
  int get nextCursor => json['nextCursor'] as int;
  int get upperBound => json['upperBound'] as int;
  int get firstAvailableId => json['firstAvailableId'] as int;
  bool get hasMore => json['hasMore'] as bool;
  bool get recording => json['recording'] == true;

  factory CompanionPage.fromJson(Map<String, dynamic> json) {
    try {
      if (json['schemaVersion'] != 2 ||
          !['usage', 'location'].contains(json['kind'])) {
        throw const FormatException();
      }
      final source = CompanionSource.fromJson(json);
      final after = json['after'] as int;
      final next = json['nextCursor'] as int;
      final upper = json['upperBound'] as int;
      final first = json['firstAvailableId'] as int;
      if (after < 0 ||
          next < after ||
          upper < next ||
          first < 0 ||
          json['hasMore'] != (next < upper)) {
        throw const FormatException();
      }
      final rows = (json['records'] as List).cast<Map<String, dynamic>>();
      if (rows.length > 100 || (next < upper && rows.isEmpty)) {
        throw const FormatException();
      }
      int previous = after;
      for (final row in rows) {
        final id = row['id'] as int;
        if (id <= previous || id > next || (row['recordedAtMs'] as int) < 0) {
          throw const FormatException();
        }
        previous = id;
        final data = row['data'] as Map<String, dynamic>;
        if (json['kind'] == 'usage') {
          final usage = UsageSnapshot.fromJson(data);
          if (usage.installationId != source.installationId ||
              usage.androidUserId != source.androidUserId) {
            throw const FormatException();
          }
        } else {
          LocationRecord.fromJson(data);
        }
      }
      if (rows.isNotEmpty && previous != next) throw const FormatException();
      return CompanionPage._(
        Map.unmodifiable(json),
        source,
        List.unmodifiable(rows),
      );
    } catch (_) {
      throw const UsageSyncException('usageInvalidResponse');
    }
  }
}

/// 手机真实定位回调的原始坐标，时间与精度始终随记录展示。
class LocationRecord {
  LocationRecord._(this.json);
  final Map<String, dynamic> json;
  double get latitude => (json['latitude'] as num).toDouble();
  double get longitude => (json['longitude'] as num).toDouble();
  double get accuracyMeters => (json['accuracyMeters'] as num).toDouble();
  int get capturedAtMs => json['capturedAtMs'] as int;
  int get receivedAtMs => json['receivedAtMs'] as int;
  bool get mock => json['mock'] as bool;
  String get provider => json['provider'] as String;
  factory LocationRecord.fromJson(Map<String, dynamic> json) {
    final latitude = (json['latitude'] as num).toDouble();
    final longitude = (json['longitude'] as num).toDouble();
    final accuracy = (json['accuracyMeters'] as num).toDouble();
    if (!latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180 ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        json['coordinateSystem'] != 'WGS84' ||
        json['mock'] is! bool ||
        json['provider'] is! String ||
        (json['capturedAtMs'] as int) <= 0 ||
        (json['receivedAtMs'] as int) <= 0 ||
        (json['capturedAtMs'] as int) > 8640000000000000 ||
        (json['receivedAtMs'] as int) > 8640000000000000) {
      throw const FormatException();
    }
    return LocationRecord._(Map.unmodifiable(json));
  }
}
