import 'package:flutter/material.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_icon.dart';
import '../../../app/widget/app_detail_layout.dart';
import '../../../core/apk/local_apk_info.dart';
import '../../../core/device_info/android_version_helper.dart';

/// 将本地 APK 静态快照转换成统一的应用详情 presentation model。
AppDetailViewData buildLocalApkDetailViewData(
  BuildContext context, {
  required LocalApkInfo info,
  required String path,
  required List<AppDetailTabData> tabs,
}) {
  final missing = context.l10n.t('apkMissing');
  final version = [
    info.text('versionName'),
    if (info.text('versionCode').isNotEmpty) '(${info.text('versionCode')})',
  ].where((part) => part.isNotEmpty).join(' ');
  final abis = info.text('abis');
  final icon = info.icon;
  final badges = <AppDetailSummaryBadge>[
    if (abis.isNotEmpty) AppDetailSummaryBadge(label: abis),
    if (info.data['debuggable'] == true)
      AppDetailSummaryBadge(
        label: context.l10n.t('apkDebug'),
        tone: AppDetailBadgeTone.error,
      ),
  ];

  String sdkValue(String key) {
    final raw = info.text(key);
    if (raw.isEmpty) return missing;
    final apiLevel = int.tryParse(raw);
    return apiLevel == null
        ? raw
        : AndroidVersionHelper.formatApiLevel(apiLevel);
  }

  String valueOrMissing(String value) => value.isEmpty ? missing : value;

  return AppDetailViewData(
    name: info.name,
    version: valueOrMissing(version),
    logo: AppDetailLogoData(
      image: icon == null ? null : MemoryImage(icon),
      fallbackImage: const AssetImage(AppIcons.androidDefaultAppIcon),
    ),
    badges: badges,
    tabs: tabs,
    fields: [
      AppDetailSummaryField(
        label: context.l10n.t('apkPackage'),
        value: valueOrMissing(info.packageName),
        copyable: info.packageName.isNotEmpty,
      ),
      AppDetailSummaryField(
        label: context.l10n.t('apkMinSdk'),
        value: sdkValue('minSdk'),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('apkTargetSdk'),
        value: sdkValue('targetSdk'),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('apkMaxSdk'),
        value: sdkValue('maxSdk'),
      ),
      AppDetailSummaryField(
        label: context.l10n.t('apkSize'),
        value:
            '${((info.data['size'] as num? ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB',
      ),
      AppDetailSummaryField(
        label: context.l10n.t('apkFile'),
        value: valueOrMissing(path),
        copyable: path.isNotEmpty,
        maxLines: 4,
      ),
    ],
  );
}
