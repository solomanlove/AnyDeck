import 'dart:convert';
import 'dart:typed_data';
import 'android_package_format.dart';

/// 本地 Android 安装包的静态快照；不包含设备安装时间、权限授权或启用状态。
class LocalApkInfo {
  LocalApkInfo(this.data);

  final Map<String, dynamic> data;
  String get packageName => text('packageName');
  String get name => text('label').isEmpty ? packageName : text('label');
  String text(String key) => data[key]?.toString() ?? '';
  String get format => text('format').isEmpty ? 'APK' : text('format');
  bool get analysisOnly => format != AndroidPackageFormat.apk.label;
  bool get installable =>
      !analysisOnly && packageName.isNotEmpty && data['split'] != true;
  List<Map<String, dynamic>> rows(String key) =>
      (data[key] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Uint8List? get icon {
    final encoded = data['icon'] as String?;
    return encoded == null ? null : base64Decode(encoded);
  }
}
