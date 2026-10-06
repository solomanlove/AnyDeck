import '../../../core/ios/ios_process_info.dart';

/// 用户/系统分类指已关联应用的类型，不等同于 Android UID。
enum IosProcessFilter { user, system, all }

enum IosProcessSort { name, pid, type, startedAt }

enum IosProcessAction { name, pid, bundle, hostBundle, path, details, kill }

/// 原始 isApplication 优先；字段缺失时仅以明确关联的应用作为补充依据。
bool iosProcessIsApp(IosProcessInfo item) =>
    item.isApplication ?? (item.app != null);

String iosProcessTypeKey(IosProcessInfo item) {
  if (item.app != null) return item.app!.system ? 'systemApp' : 'userApp';
  return item.isApplication == false ? 'iosProcessNonApp' : 'iosProcessUnknown';
}

/// 筛选名称、PID、进程及宿主 Bundle ID、路径，并按真实字段稳定排序。
List<IosProcessInfo> filterIosProcesses(
  List<IosProcessInfo> items, {
  required IosProcessFilter category,
  required bool onlyApps,
  required String query,
  required IosProcessSort sort,
  required bool ascending,
}) {
  final needle = query.trim().toLowerCase();
  final result = items.where((item) {
    if (onlyApps && !iosProcessIsApp(item)) return false;
    if (category == IosProcessFilter.user && item.app?.system != false) {
      return false;
    }
    if (category == IosProcessFilter.system && item.app?.system != true) {
      return false;
    }
    return needle.isEmpty ||
        [
          item.displayName,
          '${item.pid}',
          item.bundleId,
          item.app?.bundleId,
          item.executablePath,
        ].whereType<String>().any(
          (value) => value.toLowerCase().contains(needle),
        );
  }).toList();
  result.sort((a, b) {
    // 缺失日期始终置底，不把未知值当 epoch/零值。
    if (sort == IosProcessSort.startedAt) {
      if (a.startedAt == null && b.startedAt != null) return 1;
      if (a.startedAt != null && b.startedAt == null) return -1;
    }
    final value = switch (sort) {
      IosProcessSort.name => a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      ),
      IosProcessSort.pid => a.pid.compareTo(b.pid),
      IosProcessSort.type => iosProcessTypeKey(
        a,
      ).compareTo(iosProcessTypeKey(b)),
      IosProcessSort.startedAt =>
        a.startedAt?.compareTo(b.startedAt ?? a.startedAt!) ?? 0,
    };
    return value == 0 ? a.pid.compareTo(b.pid) : (ascending ? value : -value);
  });
  return result;
}
