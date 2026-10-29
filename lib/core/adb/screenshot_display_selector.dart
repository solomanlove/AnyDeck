/// 从 DisplayManager 快照选择当前点亮的内置物理屏幕，不缓存折叠状态。
///
/// 返回 screencap -d 使用的 physical displayId 字符串，避免与逻辑 ID
/// 混用，也避免将 uint64 ID 转换为有符号整数。旧系统无法解析时返回 null。
class ScreenshotDisplaySelector {
  static final _deviceInfo = RegExp(
    r'^\s*DisplayDeviceInfo\{[^\r\n]*',
    multiLine: true,
  );
  static final _physicalId = RegExp(r'uniqueId="local:(\d+)"');
  static final _internal = RegExp(r'\btype\s+(?:INTERNAL|BUILT_IN)\b');
  static final _on = RegExp(r',\s*state\s+ON\b');
  static final _primary = RegExp(
    r'mDisplayId=0\s*\r?\n\s*mPrimaryDisplayDevice=[^\r\n]*\(local:(\d+)\)',
  );

  /// 仅选择 ON 的内置屏；多个内置屏同时点亮时优先逻辑主屏对应的物理屏。
  static String? select(String displayDump) {
    final activeIds = <String>[];
    for (final match in _deviceInfo.allMatches(displayDump)) {
      final info = match.group(0)!;
      if (!_internal.hasMatch(info) || !_on.hasMatch(info)) continue;
      final id = _physicalId.firstMatch(info)?.group(1);
      if (id != null) activeIds.add(id);
    }
    if (activeIds.isEmpty) return null;
    final primaryId = _primary.firstMatch(displayDump)?.group(1);
    return activeIds.contains(primaryId) ? primaryId : activeIds.first;
  }
}
