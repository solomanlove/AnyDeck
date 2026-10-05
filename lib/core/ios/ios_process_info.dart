import 'ios_app_info.dart';

/// iOS 运行进程及其所属应用；扩展自身的 Bundle ID 与宿主信息分开保存。
class IosProcessInfo {
  const IosProcessInfo({
    required this.pid,
    required this.name,
    this.executablePath,
    this.startedAt,
    this.isApplication,
    this.bundleId,
    this.app,
  });

  final int pid;
  final String name;
  final String? executablePath;
  final DateTime? startedAt;
  final bool? isApplication;
  final String? bundleId;
  final IosAppInfo? app;

  bool get isExtension => executablePath?.contains('.appex/') ?? false;

  String get displayName =>
      app != null && app!.name != name ? '${app!.name} · $name' : name;

  /// 关联应用不会覆盖进程自身的名称、Bundle ID 和执行路径。
  IosProcessInfo withApp(IosAppInfo? value) => IosProcessInfo(
    pid: pid,
    name: name,
    executablePath: executablePath,
    startedAt: startedAt,
    isApplication: isApplication,
    bundleId: bundleId,
    app: value,
  );
}
