import 'adb_app_permission.dart';

/// 按区块缩进解析当前用户权限，避免其他用户或组件污染授权状态。
List<AdbAppPermission> parseAppPermissions(
  String output,
  int userId, {
  Map<String, bool> permissionTypes = const {},
}) {
  final requested = <String>{};
  final permissions = <String, AdbAppPermission>{};
  String? block;
  var blockIndent = -1;
  int? activeUser;
  final userHeader = RegExp(r'^User (\d+):');
  final permissionName = RegExp(r'^[\w.]+$');
  for (final line in output.split('\n')) {
    final value = line.trim();
    if (value.isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    if (indent <= blockIndent) block = null;
    final user = userHeader.firstMatch(value);
    if (user != null) {
      activeUser = int.parse(user.group(1)!);
      block = null;
      continue;
    }
    if (indent <= 4) activeUser = null;
    if (value == 'requested permissions:' ||
        value == 'install permissions:' ||
        value == 'runtime permissions:') {
      block = value;
      blockIndent = indent;
      continue;
    }
    if (block == null || (activeUser != null && activeUser != userId)) {
      continue;
    }
    if (block == 'requested permissions:' && permissionName.hasMatch(value)) {
      requested.add(value);
    } else if (block != 'requested permissions:') {
      if (block == 'runtime permissions:' && activeUser != userId) continue;
      final colon = value.indexOf(':');
      if (colon < 0) continue;
      final name = value.substring(0, colon);
      if (!permissionName.hasMatch(name) || !value.contains('granted=')) {
        continue;
      }
      permissions[name] = AdbAppPermission(
        name: name,
        granted: value.contains('granted=true'),
        isRuntime: block == 'runtime permissions:',
        isFixed: RegExp(r'\b(SYSTEM_FIXED|POLICY_FIXED)\b').hasMatch(value),
      );
    }
  }
  for (final name in requested) {
    permissions.putIfAbsent(
      name,
      () => AdbAppPermission(
        name: name,
        granted: false,
        isRuntime: permissionTypes[name] ?? false,
        isKnownType: permissionTypes.containsKey(name),
      ),
    );
  }
  final result = permissions.values.toList();
  result.sort((a, b) => a.name.compareTo(b.name));
  return result;
}

/// 使用设备自身的 protectionLevel 分类，兼容新增和厂商自定义权限。
Map<String, bool> parsePermissionTypes(String output) {
  final types = <String, bool>{};
  String? name;
  for (final line in output.split('\n')) {
    final value = line.trim();
    final match = RegExp(r'^\+?\s*permission:(\S+)$').firstMatch(value);
    if (match != null) {
      name = match.group(1);
    } else if (name != null && value.startsWith('protectionLevel:')) {
      final level = value.substring('protectionLevel:'.length).trim();
      if (level.isNotEmpty) {
        types[name] = level.split('|').contains('dangerous');
      }
      name = null;
    }
  }
  return types;
}
