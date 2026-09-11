/// 应用权限元数据。
class AdbAppPermission {
  const AdbAppPermission({
    required this.name,
    required this.granted,
    required this.isRuntime,
    this.isKnownType = true,
    this.isFixed = false,
  });

  /// 权限名称，例如 `android.permission.CAMERA`。
  final String name;

  /// 是否已授权。
  final bool granted;

  /// 是否为运行时权限（仅运行时权限可通过 adb pm grant/revoke 修改）。
  final bool isRuntime;

  /// 未知类型保持只读，系统或策略固定权限不可修改。
  final bool isKnownType;
  final bool isFixed;
  bool get canChange => isKnownType && isRuntime && !isFixed;

  @override
  String toString() => 'AdbAppPermission(name: $name, granted: $granted, isRuntime: $isRuntime)';
}
