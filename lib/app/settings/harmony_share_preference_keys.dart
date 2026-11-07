/// 鸿蒙互联设置的唯一存储 key；由 AppSettingsController 写入，核心服务按轮读取。
abstract final class HarmonySharePreferenceKeys {
  static const notifications = 'settings.harmonyShareNotifications';
  static const receiveDirectory = 'settings.harmonyShareReceiveDirectory';
  static const localName = 'settings.harmonyShareLocalName';
  static const directMode = 'settings.harmonyShareDirectMode';
}
