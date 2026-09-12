import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/usage/companion_history.dart';

/// 弹窗内的展示选择与地图打开状态，关闭弹窗后自动释放。
final usageReportViewProvider = NotifierProvider.autoDispose
    .family<UsageReportViewController, UsageReportViewState, String>(
      UsageReportViewController.new,
    );

class UsageReportViewState {
  const UsageReportViewState({this.tab = 0, this.day, this.openingMap = false});
  final int tab;
  final String? day;
  final bool openingMap;
}

/// 用户主动点击时复用已有浏览器服务，不自动加载网络地图。
class UsageReportViewController extends Notifier<UsageReportViewState> {
  UsageReportViewController(this.deviceId);
  final String deviceId;

  @override
  UsageReportViewState build() => const UsageReportViewState();

  void selectTab(int tab) {
    state = UsageReportViewState(
      tab: tab,
      day: state.day,
      openingMap: state.openingMap,
    );
  }

  void selectDay(String? day) {
    state = UsageReportViewState(
      tab: state.tab,
      day: day,
      openingMap: state.openingMap,
    );
  }

  Future<bool> openMap(LocationRecord point) async {
    if (state.openingMap) return true;
    state = UsageReportViewState(
      tab: state.tab,
      day: state.day,
      openingMap: true,
    );
    try {
      await ref
          .read(webDebugServiceProvider)
          .openBrowser(
            'https://www.openstreetmap.org/#map=17/${point.latitude}/${point.longitude}',
          );
      return true;
    } catch (_) {
      return false;
    } finally {
      if (ref.mounted) {
        state = UsageReportViewState(tab: state.tab, day: state.day);
      }
    }
  }
}
