/// go-ios 返回的 iOS 运行进程基础信息。
class IosProcessInfo {
  const IosProcessInfo({required this.pid, required this.name});

  final int pid;
  final String name;
}
