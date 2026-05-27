import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('zh'), Locale('en')];

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  String t(String key) {
    final languageCode = locale.languageCode == 'en' ? 'en' : 'zh';
    return _localizedValues[languageCode]?[key] ??
        _localizedValues['zh']?[key] ??
        key;
  }
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}

const _localizedValues = {
  'zh': {
    'settings': '设置',
    'language': '语言',
    'chinese': '中文',
    'english': 'English',
    'theme': '外观',
    'themeSystem': '跟随系统',
    'themeLight': '浅色模式',
    'themeDark': '深色模式',
    'close': '关闭',
    'devices': '设备',
    'files': '文件',
    'logcat': '日志',
    'control': '控制',
    'apps': '应用',
    'refreshDevices': '刷新设备',
    'connectTcp': '通过 TCP/IP 连接',
    'scanningDevices': '正在扫描 ADB 设备',
    'adbUnavailable': 'ADB 不可用',
    'noDevices': '未发现 Android 设备',
    'connectUsbOrTcp': '请连接 USB 设备或使用 TCP/IP 连接。',
    'connectDevice': '连接设备',
    'ipAddress': 'IP 地址',
    'cancel': '取消',
    'connect': '连接',
    'selectDevice': '选择设备',
    'selectDeviceHint': '选择设备后可使用调试工具面板。',
    'scrcpyLauncher': 'scrcpy 投屏',
    'start': '启动',
    'stop': '停止',
    'stopAll': '全部停止',
    'scrcpyStarted': 'scrcpy 已启动',
    'scrcpyStopped': 'scrcpy 会话已停止',
    'deviceActions': '设备操作',
    'inputText': '输入文本',
    'home': '主页',
    'back': '返回',
    'power': '电源',
    'volumeUp': '音量 +',
    'volumeDown': '音量 -',
    'wifiOn': 'Wi-Fi 开',
    'wifiOff': 'Wi-Fi 关',
    'text': '文本',
    'send': '发送',
    'layoutHelper': '布局辅助',
    'boundsOn': '布局边界开',
    'boundsOff': '布局边界关',
    'darkMode': '深色',
    'lightMode': '浅色',
    'deviceInfo': '设备信息',
    'androidId': 'Android ID',
    'version': '版本',
    'focus': '前台窗口',
    'reboot': '重启',
    'rebootDevice': '确定重启设备？',
    'filterPackage': '筛选包名',
    'installApk': '安装 APK',
    'refreshPackages': '刷新应用列表',
    'loadingPackages': '正在加载应用',
    'packageListFailed': '应用列表加载失败',
    'noPackages': '未发现应用',
    'launch': '启动',
    'forceStop': '强停',
    'packagePath': '安装路径',
    'clearData': '清除数据',
    'clearDataFor': '确定清除 {package} 的数据？',
    'uninstall': '卸载',
    'uninstallPackage': '确定卸载 {package}？',
    'refresh': '刷新',
    'push': '上传',
    'loadingFiles': '正在加载文件',
    'fileListFailed': '文件列表加载失败',
    'emptyFolder': '空目录',
    'pull': '下载',
    'delete': '删除',
    'deleteFile': '确定删除 {file}？',
    'clear': '清空',
    'filterLog': '筛选日志',
    'result': '结果',
    'error': '错误',
    'confirm': '确认',
  },
  'en': {
    'settings': 'Settings',
    'language': 'Language',
    'chinese': '中文',
    'english': 'English',
    'theme': 'Theme',
    'themeSystem': 'System',
    'themeLight': 'Light',
    'themeDark': 'Dark',
    'close': 'Close',
    'devices': 'Devices',
    'files': 'Files',
    'logcat': 'Logcat',
    'control': 'Control',
    'apps': 'Apps',
    'refreshDevices': 'Refresh devices',
    'connectTcp': 'Connect over TCP/IP',
    'scanningDevices': 'Scanning adb devices',
    'adbUnavailable': 'ADB unavailable',
    'noDevices': 'No Android devices',
    'connectUsbOrTcp': 'Connect USB or use TCP/IP connect.',
    'connectDevice': 'Connect device',
    'ipAddress': 'IP address',
    'cancel': 'Cancel',
    'connect': 'Connect',
    'selectDevice': 'Select a device',
    'selectDeviceHint': 'Device actions and toolbox panels appear here.',
    'scrcpyLauncher': 'scrcpy launcher',
    'start': 'Start',
    'stop': 'Stop',
    'stopAll': 'Stop all',
    'scrcpyStarted': 'scrcpy started',
    'scrcpyStopped': 'scrcpy session stopped',
    'deviceActions': 'Device actions',
    'inputText': 'Input text',
    'home': 'Home',
    'back': 'Back',
    'power': 'Power',
    'volumeUp': 'Volume +',
    'volumeDown': 'Volume -',
    'wifiOn': 'Wi-Fi on',
    'wifiOff': 'Wi-Fi off',
    'text': 'Text',
    'send': 'Send',
    'layoutHelper': 'Layout helper',
    'boundsOn': 'Bounds on',
    'boundsOff': 'Bounds off',
    'darkMode': 'Dark mode',
    'lightMode': 'Light mode',
    'deviceInfo': 'Device info',
    'androidId': 'Android ID',
    'version': 'Version',
    'focus': 'Focus',
    'reboot': 'Reboot',
    'rebootDevice': 'Reboot device?',
    'filterPackage': 'Filter package',
    'installApk': 'Install APK',
    'refreshPackages': 'Refresh packages',
    'loadingPackages': 'Loading packages',
    'packageListFailed': 'Package list failed',
    'noPackages': 'No packages',
    'launch': 'Launch',
    'forceStop': 'Force stop',
    'packagePath': 'Package path',
    'clearData': 'Clear data',
    'clearDataFor': 'Clear data for {package}?',
    'uninstall': 'Uninstall',
    'uninstallPackage': 'Uninstall {package}?',
    'refresh': 'Refresh',
    'push': 'Push',
    'loadingFiles': 'Loading files',
    'fileListFailed': 'File list failed',
    'emptyFolder': 'Empty folder',
    'pull': 'Pull',
    'delete': 'Delete',
    'deleteFile': 'Delete {file}?',
    'clear': 'Clear',
    'filterLog': 'Filter log',
    'result': 'Result',
    'error': 'Error',
    'confirm': 'Confirm',
  },
};
