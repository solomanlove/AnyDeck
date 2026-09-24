part of '../dashboard_screen.dart';

class _PackageTableWidths {
  const _PackageTableWidths({
    this.checkbox = 44.0,
    required this.appName,
    required this.version,
    required this.minSdk,
    required this.targetSdk,
    required this.storage,
  });

  factory _PackageTableWidths.adaptive({
    required BuildContext context,
    required List<AdbPackage> packages,
    required double viewportWidth,
    int? totalCount,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final headerStyle = textTheme.titleSmall;
    final bodyStyle = textTheme.bodyMedium;
    final l10n = context.l10n;

    double headerWidth(String key) =>
        _measureTableText(l10n.t(key), headerStyle);

    double contentWidth(Iterable<String> values) {
      var width = 0.0;
      for (final value in values) {
        width = max(width, _measureTableText(value, bodyStyle));
      }
      return width;
    }

    final appNameHeader = totalCount != null
        ? '${l10n.t('appName')} (${l10n.t('appCount').replaceAll('{visible}', '${packages.length}').replaceAll('{total}', '$totalCount')})'
        : l10n.t('appName');
    final appName = max(
      max(
        _measureTableText(appNameHeader, headerStyle),
        contentWidth(packages.map((package) => package.displayName)),
      ),
      contentWidth(packages.map((package) => package.name)),
    ).clamp(240.0, 420.0);
    final version = max(
      headerWidth('version'),
      contentWidth(packages.map((package) => package.versionLabel)),
    ).clamp(88.0, 150.0);
    final minSdk = max(
      headerWidth('minSdkVersion'),
      contentWidth(packages.map((package) => _sdkLabel(package.minSdk))),
    ).clamp(88.0, 112.0);
    final targetSdk = max(
      headerWidth('targetMaxSdk'),
      contentWidth(packages.map(_targetMaxSdkLabel)),
    ).clamp(108.0, 136.0);
    final storage = max(
      headerWidth('storageUsed'),
      contentWidth(packages.map((package) => package.storageLabel)),
    ).clamp(104.0, 136.0);
    const checkboxWidth = 44.0;
    final base = _PackageTableWidths(
      checkbox: checkboxWidth,
      appName: appName + _PackageCell.horizontalPadding + 38,
      version: version + _PackageCell.horizontalPadding,
      minSdk: minSdk + _PackageCell.horizontalPadding,
      targetSdk: targetSdk + _PackageCell.horizontalPadding + 38,
      storage: storage + _PackageCell.horizontalPadding,
    );

    if (base.total > viewportWidth) {
      final overflow = base.total - viewportWidth;
      final appNameShrink = min(overflow, base.appName - 240.0);
      return base.copyWith(
        appName: base.appName - appNameShrink,
      );
    }

    final spareWidth = viewportWidth - base.total;
    return base.copyWith(
      appName: base.appName + spareWidth,
    );
  }

  final double checkbox;
  final double appName;
  final double version;
  final double minSdk;
  final double targetSdk;
  final double storage;

  double get total =>
      checkbox +
      appName +
      version +
      minSdk +
      targetSdk +
      storage;

  _PackageTableWidths copyWith({double? appName}) {
    return _PackageTableWidths(
      checkbox: checkbox,
      appName: appName ?? this.appName,
      version: version,
      minSdk: minSdk,
      targetSdk: targetSdk,
      storage: storage,
    );
  }
}

double _measureTableText(String value, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

/// 表头行，所有列都明确宽度，避免短列标题被压成竖排。
