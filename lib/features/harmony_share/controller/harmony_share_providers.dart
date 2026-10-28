import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/nearby_share/harmony_share_notifications.dart';
import '../../../core/nearby_share/harmony_share_service.dart';
import '../../../core/notifications/notification_providers.dart';

/// 仅主窗口启用；持有全局通知桥接引用，不创建或销毁桥接实例。
final harmonyShareNotificationsProvider = Provider<HarmonyShareNotifications>((
  ref,
) {
  final notifications = HarmonyShareNotifications(
    service: HarmonyShareService.instance,
    queue: HarmonyShareService.instance.sendQueue,
    bridge: ref.read(macNotificationBridgeProvider),
    enabled: () => ref.read(appSettingsProvider).harmonyShareNotifications,
    text: (key) =>
        AppLocalizations(ref.read(appSettingsProvider).language.locale).t(key),
  );
  ref.listen(
    appSettingsProvider.select(
      (settings) => settings.harmonyShareNotifications,
    ),
    (_, _) => notifications.settingsChanged(),
  );
  ref.onDispose(notifications.dispose);
  return notifications;
});
