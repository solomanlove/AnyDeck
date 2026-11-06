import 'package:flutter/material.dart';

import '../../../core/nearby_share/harmony_share_incoming_notifications.dart';
import '../../../core/nearby_share/harmony_share_service.dart';
import '../widgets/harmony_share_panels.dart';
import '../widgets/harmony_share_format.dart';
import '../../../app/l10n/app_localizations.dart';

/// 主窗口来件兜底弹窗；通知协调器决定显示时机，失效时只关闭自己的 Route。
class HarmonyShareOfferPresenter {
  HarmonyShareOfferPresenter({required this.incoming, required this.context}) {
    incoming.addListener(handle);
    handle();
  }
  final HarmonyShareIncomingNotifications incoming;
  HarmonyShareService get service => incoming.service;
  final BuildContext Function() context;
  ShareIncomingOffer? _shown;
  DialogRoute<bool>? _route;
  bool _disposed = false;

  void handle() {
    final offer = incoming.offer;
    if (offer == null || !incoming.needsConfirmation) {
      _shown = null;
      _close();
      return;
    }
    if (_disposed || identical(_shown, offer)) return;
    _close();
    _shown = offer;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_disposed || service.pendingOffer != offer ||
          !incoming.needsConfirmation) {
        return;
      }
      final root = context();
      if (!root.mounted) return;
      final route = DialogRoute<bool>(
        context: root,
        barrierDismissible: false,
        builder: (_) => HarmonyShareConfirmDialog(
          receiving: true,
          device:
              service.peers[offer.address.address]?.name ??
              offer.address.address,
          summary: root.l10n.t('harmonyShareSelectionSummary').replaceAll('{count}', '${offer.fileCount}').replaceAll('{size}', formatShareBytes(offer.bytes)),
        ),
      );
      _route = route;
      final accepted = await Navigator.of(
        root,
        rootNavigator: true,
      ).push(route);
      if (identical(_route, route)) {
        _route = null;
      }
      if (!_disposed && service.pendingOffer == offer) {
        incoming.decide(offer, accepted == true);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _close() {
    final route = _route;
    _route = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route, false);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    _disposed = true;
    incoming.removeListener(handle);
    _close();
  }
}
