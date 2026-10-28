import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/nearby_share/harmony_share_service.dart';
import '../widgets/harmony_share_panels.dart';
import '../widgets/harmony_share_format.dart';
import '../../../app/l10n/app_localizations.dart';

/// 主窗口来件弹窗协调器；请求失效/超时只关闭自己的 Route，不误关用户其他弹窗。
class HarmonyShareOfferPresenter {
  HarmonyShareOfferPresenter({required this.service, required this.context}) {
    service.addListener(handle);
    handle();
  }
  final HarmonyShareService service;
  final BuildContext Function() context;
  ShareIncomingOffer? _shown;
  DialogRoute<bool>? _route;
  Timer? _timeout;
  bool _disposed = false;

  void handle() {
    final offer = service.pendingOffer;
    if (offer == null) {
      _close();
      return;
    }
    if (_disposed || identical(_shown, offer)) return;
    _shown = offer;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_disposed || service.pendingOffer != offer) return;
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
      _timeout = Timer(
        const Duration(seconds: 30),
        () => service.expireOffer(offer),
      );
      final accepted = await Navigator.of(
        root,
        rootNavigator: true,
      ).push(route);
      if (identical(_route, route)) {
        _route = null;
        _timeout?.cancel();
      }
      if (!_disposed && service.pendingOffer == offer) {
        service.decide(accepted == true);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _close() {
    final route = _route;
    _route = null;
    _timeout?.cancel();
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
    service.removeListener(handle);
    _close();
  }
}
