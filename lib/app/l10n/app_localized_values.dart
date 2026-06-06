import 'tables/app_l10n_settings.dart';
import 'tables/app_l10n_devices_control.dart';
import 'tables/app_l10n_apps_files_logcat.dart';
import 'tables/app_l10n_overview_terminal_emulators.dart';
import 'tables/app_l10n_tools_mirror.dart';

/// 全部 UI 文案字符串表。Widget 直接按 key 访问，key 应保持稳定。
///
/// 注意：
/// 1. 新增文案时不要修改既有 key 名称，否则现有 context.l10n.t('key') 调用会回退为 key 本身。
/// 2. 同一个 key 只允许放在一个模块表中；Map spread 后面的值会覆盖前面的值。
/// 3. zh/en 必须同步补齐，避免英文缺失时长期依赖中文 fallback。
///
/// 轻量测试：
/// 1. dart format lib/app/l10n
/// 2. flutter analyze
const localizedValues = {
  'zh': {
    ...settingsZh,
    ...devicesControlZh,
    ...appsFilesLogcatZh,
    ...overviewTerminalEmulatorsZh,
    ...toolsMirrorZh,
  },
  'en': {
    ...settingsEn,
    ...devicesControlEn,
    ...appsFilesLogcatEn,
    ...overviewTerminalEmulatorsEn,
    ...toolsMirrorEn,
  },
};
