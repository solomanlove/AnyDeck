part of '../dashboard_screen.dart';

class _PackageTableWidths {
  const _PackageTableWidths({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.minSdk,
    required this.targetSdk,
    required this.storage,
    required this.status,
    required this.type,
  });

  factory _PackageTableWidths.adaptive({
    required BuildContext context,
    required List<AdbPackage> packages,
    required double viewportWidth,
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

    final appName = max(
      headerWidth('appName'),
      contentWidth(packages.map((package) => package.displayName)),
    ).clamp(160.0, 320.0);
    final packageName = max(
      headerWidth('packageName'),
      contentWidth(packages.map((package) => package.name)),
    ).clamp(240.0, 520.0);
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
    final status = max(
      headerWidth('status'),
      contentWidth(
        packages.map(
          (package) => package.enabled ? l10n.t('enabled') : l10n.t('disabled'),
        ),
      ),
    ).clamp(104.0, 128.0);
    final type = max(
      headerWidth('appType'),
      contentWidth(
        packages.map(
          (package) => [
            package.system ? l10n.t('systemApp') : l10n.t('userApp'),
            package.flutter ? l10n.t('flutterApp') : l10n.t('nativeApp'),
          ].join(' / '),
        ),
      ),
    ).clamp(128.0, 164.0);
    final base = _PackageTableWidths(
      appName: appName + _PackageCell.horizontalPadding + 38,
      packageName: packageName + _PackageCell.horizontalPadding,
      version: version + _PackageCell.horizontalPadding,
      minSdk: minSdk + _PackageCell.horizontalPadding,
      targetSdk: targetSdk + _PackageCell.horizontalPadding + 38,
      storage: storage + _PackageCell.horizontalPadding,
      status: status + _PackageCell.horizontalPadding,
      type: type + _PackageCell.horizontalPadding,
    );

    if (base.total > viewportWidth) {
      var overflow = base.total - viewportWidth;
      final packageShrink = min(overflow, base.packageName - 244.0);
      overflow -= packageShrink;
      final appNameShrink = min(overflow, base.appName - 222.0);
      return base.copyWith(
        appName: base.appName - appNameShrink,
        packageName: base.packageName - packageShrink,
      );
    }

    final spareWidth = viewportWidth - base.total;
    return base.copyWith(
      appName: base.appName + spareWidth * 0.4,
      packageName: base.packageName + spareWidth * 0.6,
    );
  }

  final double appName;
  final double packageName;
  final double version;
  final double minSdk;
  final double targetSdk;
  final double storage;
  final double status;
  final double type;

  double get total =>
      appName +
      packageName +
      version +
      minSdk +
      targetSdk +
      storage +
      status +
      type;

  _PackageTableWidths copyWith({double? appName, double? packageName}) {
    return _PackageTableWidths(
      appName: appName ?? this.appName,
      packageName: packageName ?? this.packageName,
      version: version,
      minSdk: minSdk,
      targetSdk: targetSdk,
      storage: storage,
      status: status,
      type: type,
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
