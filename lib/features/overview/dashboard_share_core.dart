part of '../dashboard_screen.dart';

/// 按编译入口决定是否创建互传服务及通知监听，禁用时不触碰私有组件。
extension _DashboardShareCore on _DashboardScreenState {
  void _initializeShareCore() {
    if (!AnyDeckBuildFeatures.shareCore) return;
    _shareOfferPresenter = HarmonyShareOfferPresenter(
      incoming: ref.read(harmonyShareNotificationsProvider).incoming,
      context: () => context,
    );
    unawaited(HarmonyShareService.instance.start());
  }

  void _disposeShareCore() {
    if (!AnyDeckBuildFeatures.shareCore) return;
    _shareOfferPresenter?.dispose();
    unawaited(HarmonyShareService.instance.stop());
  }

  bool _handleShareCoreNotification(Map<String, dynamic> payload) {
    if (!AnyDeckBuildFeatures.shareCore) return false;
    if (ref
        .read(harmonyShareNotificationsProvider)
        .incoming
        .handleClick(payload)) {
      return true;
    }
    return routeHarmonyShareNotification(payload, () {
      if (mounted) context.goNamed(AppRouteNames.harmonyShare);
    });
  }
}
