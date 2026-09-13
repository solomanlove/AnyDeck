import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_localized_values.dart';

/// 轻量本地化封装，底层使用拆分后的内存字符串表。
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  /// 当前应用内置中文和英文。
  static const supportedLocales = [Locale('zh'), Locale('en')];

  /// 从 BuildContext 读取最近的本地化对象。
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  /// 按 key 取文案，英文缺失时回退中文，保证 UI 可用。
  String t(String key) {
    // Determine language code, defaulting to Chinese if unsupported.
    var languageCode = locale.languageCode;
    if (!localizedValues.containsKey(languageCode)) {
      languageCode = 'zh';
    }
    // Look up the key in the selected language map.
    final langMap = localizedValues[languageCode]!;
    // Return the localized string, fall back to Chinese or the key itself.
    return langMap[key] ?? localizedValues['zh']![key] ?? key;
  }
}

/// 给 Widget 提供更短的本地化访问入口。
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// 同步本地化代理，因为所有翻译都已内置在内存字符串表中。
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
