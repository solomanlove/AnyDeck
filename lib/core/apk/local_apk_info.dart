import 'dart:convert';
import 'dart:typed_data';

/// 本地 APK 的静态快照；不包含设备安装时间、权限授权或启用状态。
class LocalApkInfo {
  LocalApkInfo(this.data);

  final Map<String, dynamic> data;
  String get packageName => text('packageName');
  String get name => text('label').isEmpty ? packageName : text('label');
  String text(String key) => data[key]?.toString() ?? '';
  bool get installable => packageName.isNotEmpty && data['split'] != true;
  List<Map<String, dynamic>> rows(String key) =>
      (data[key] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Uint8List? get icon {
    final encoded = data['icon'] as String?;
    return encoded == null ? null : base64Decode(encoded);
  }
}
