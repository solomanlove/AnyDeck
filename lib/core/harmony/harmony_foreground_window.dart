/// HarmonyOS 当前前台窗口的友好摘要。
class HarmonyForegroundWindow {
  const HarmonyForegroundWindow({
    this.bundleName,
    this.abilityName,
    this.pageName,
    this.windowName,
  });

  final String? bundleName;
  final String? abilityName;
  final String? pageName;
  final String? windowName;

  bool get isEmpty =>
      bundleName == null &&
      abilityName == null &&
      pageName == null &&
      windowName == null;

  static HarmonyForegroundWindow parse(String output) {
    String? read(List<String> labels) {
      for (final label in labels) {
        final match = RegExp(
          '(?:^|\\s)$label\\s*[:=]\\s*["\\[]?([^"\\]\\s,}]+)',
          caseSensitive: false,
          multiLine: true,
        ).firstMatch(output);
        final value = match?.group(1)?.trim();
        if (value != null && value.isNotEmpty && value != 'null') return value;
      }
      return null;
    }

    final component = RegExp(
      r'([a-zA-Z][\w]*(?:\.[\w]+){2,})/([a-zA-Z][\w.]*(?:Ability|Page))',
    ).firstMatch(output);
    return HarmonyForegroundWindow(
      bundleName:
          read(const ['bundleName', 'bundle', 'packageName']) ??
          component?.group(1),
      abilityName:
          read(const ['abilityName', 'ability']) ?? component?.group(2),
      pageName: read(const [
        'pageName',
        'pagePath',
        'routeName',
        'routerPage',
        'currentPage',
      ]),
      windowName: read(const ['windowName', 'name']),
    );
  }
}
