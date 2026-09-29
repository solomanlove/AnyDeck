import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ios/ios_app_info.dart';
import '../../../core/ios/ios_icon_service.dart';
import '../../../core/ios/ios_mirror_service.dart';
import '../../../core/search/dashboard_search_history_controller.dart';
import '../../apps/controller/app_favorites_controller.dart';

/// 按 UDID 隔离应用和图标加载；刷新、切换设备或离开页面会取消旧请求。
final iosAppsProvider = StreamProvider.autoDispose
    .family<List<IosAppInfo>, String>((ref, udid) async* {
      final request = IosIconRequest();
      ref.onCancel(request.cancel);
      ref.onDispose(request.cancel);
      final service = ref.read(iosIconServiceProvider);
      final apps = await ref.read(iosCommandServiceProvider).listApps(udid);
      if (request.cancelled) return;
      yield apps
          .map(
            (app) => app.copyWith(
              iconPath: service.getCachedIconPath(udid, app.bundleId),
            ),
          )
          .toList();
      Map<String, String> icons;
      try {
        icons = await service.fetchIcons(
          udid,
          apps.map((app) => app.bundleId).toList(),
          request: request,
        );
      } catch (_) {
        // 图标属于可选增强；缓存目录或 helper 不可用时仍保留可操作的应用列表。
        return;
      }
      if (request.cancelled || icons.isEmpty) return;
      yield apps
          .map((app) => app.copyWith(iconPath: icons[app.bundleId]))
          .toList();
    });

/// iOS 收藏与 Android 包名隔离；同一 Bundle ID 在多台 iPhone 上共用收藏。
final iosAppFavoritesProvider =
    AsyncNotifierProvider<AppFavoritesNotifier, Set<String>>(
      () => AppFavoritesNotifier(storageKey: 'ios.apps.favoriteBundleIds.v1'),
    );

/// iOS 搜索历史不混入 Android 的 DEBUG 快捷项。
class IosAppsSearchHistoryNotifier extends DashboardSearchHistoryNotifier {
  @override
  String get key => 'ios_apps_search_history';
}

final iosAppsSearchHistoryProvider =
    AsyncNotifierProvider<IosAppsSearchHistoryNotifier, List<String>>(
      IosAppsSearchHistoryNotifier.new,
    );
