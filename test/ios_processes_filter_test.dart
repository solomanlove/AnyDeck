import 'package:any_deck/core/ios/ios_app_info.dart';
import 'package:any_deck/core/ios/ios_process_info.dart';
import 'package:any_deck/features/ios/model/ios_processes_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const items = [
    IosProcessInfo(
      pid: 10,
      name: 'Extension',
      isApplication: true,
      executablePath: '/Apps/Host.app/PlugIns/A.appex/A',
      bundleId: 'com.example.extension',
      app: IosAppInfo(bundleId: 'com.example.host', name: '用户'),
    ),
    IosProcessInfo(
      pid: 2,
      name: 'System',
      isApplication: true,
      app: IosAppInfo(bundleId: 'com.example.system', name: '系统', system: true),
    ),
    IosProcessInfo(pid: 1, name: 'daemon', isApplication: false),
    IosProcessInfo(pid: 3, name: 'com.apple.unknown'),
  ];
  List<IosProcessInfo> filtered({
    IosProcessFilter category = IosProcessFilter.all,
    bool onlyApps = false,
    String query = '',
    bool ascending = true,
  }) => filterIosProcesses(
    items,
    category: category,
    onlyApps: onlyApps,
    query: query,
    sort: IosProcessSort.pid,
    ascending: ascending,
  );

  test('未知归属/非应用不猜成系统，应用标志及分类取交集', () {
    expect(filtered(category: IosProcessFilter.system).map((p) => p.pid), [2]);
    expect(filtered(category: IosProcessFilter.user).map((p) => p.pid), [10]);
    expect(filtered(onlyApps: true).map((p) => p.pid), [2, 10]);
    expect(iosProcessTypeKey(items[2]), 'iosProcessNonApp');
    expect(iosProcessTypeKey(items[3]), 'iosProcessUnknown');
  });
  test('搜索涵盖进程/宿主 Bundle ID、名称、PID 和路径，数值 PID 排序', () {
    for (final query in [
      ' 用户 ',
      'COM.EXAMPLE.EXTENSION',
      'com.example.host',
      '10',
      '.appex/',
    ]) {
      expect(filtered(query: query).single.pid, 10);
    }
    expect(filtered().map((p) => p.pid), [1, 2, 3, 10]);
    expect(filtered(ascending: false).map((p) => p.pid), [10, 3, 2, 1]);
  });
  test('启动时间未知始终置底，启动时间不冒充 CPU 时间', () {
    final dated = [
      items.last,
      IosProcessInfo(pid: 8, name: 'dated', startedAt: DateTime(2026)),
    ];
    for (final ascending in [true, false]) {
      expect(
        filterIosProcesses(
          dated,
          category: IosProcessFilter.all,
          onlyApps: false,
          query: '',
          sort: IosProcessSort.startedAt,
          ascending: ascending,
        ).last.pid,
        3,
      );
    }
  });
}
