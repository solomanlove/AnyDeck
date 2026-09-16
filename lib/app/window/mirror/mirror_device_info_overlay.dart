import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device_info/device_overview.dart';
import '../../../core/providers/app_providers.dart';
import '../../l10n/app_localizations.dart';

/// 在投屏画面上展示设备概览，数据复用概览 Provider 的本地缓存与单次刷新。
class MirrorDeviceInfoOverlay extends ConsumerWidget {
  const MirrorDeviceInfoOverlay({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(deviceOverviewProvider(deviceId));

    return overviewAsync.when(
      data: (overview) =>
          MirrorDeviceInfoCard(overview: overview, fallbackName: deviceName),
      loading: () => _MirrorDeviceInfoLoadingCard(deviceName: deviceName),
      error: (_, _) => _MirrorDeviceInfoLoadingCard(
        deviceName: deviceName,
        showLoading: false,
      ),
    );
  }
}

/// 设备信息卡只负责数据展示，避免投屏 Texture 因数据刷新而重建。
class MirrorDeviceInfoCard extends StatelessWidget {
  const MirrorDeviceInfoCard({
    super.key,
    required this.overview,
    required this.fallbackName,
  });

  final DeviceOverview overview;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    final name = _valueOrFallback(overview.name, fallbackName);
    final brandAndModel = _joinBrandAndModel(overview.brand, overview.model);
    final display = _joinDisplay(overview.rawResolution, overview.refreshRate);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DefaultTextStyle(
        style: textTheme.bodyMedium!.copyWith(
          color: colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            if (brandAndModel.isNotEmpty) Text(brandAndModel),
            if (display.isNotEmpty) Text(display),
            if (_hasValue(overview.memory))
              Text('${context.l10n.t('memory')}：${overview.memory}'),
            if (_hasValue(overview.androidVersion))
              Text(
                overview.androidVersion,
                maxLines: null,
                softWrap: true,
              ),
            if (_hasValue(overview.storage))
              Text('${context.l10n.t('storage')}：${overview.storage}'),
          ],
        ),
      ),
    );
  }

  static String _valueOrFallback(String value, String fallback) {
    return _hasValue(value) ? value : fallback;
  }

  static String _joinBrandAndModel(String brand, String model) {
    final hasBrand = _hasValue(brand);
    final hasModel = _hasValue(model);
    if (hasBrand && hasModel) return '$brand ($model)';
    if (hasBrand) return brand;
    if (hasModel) return model;
    return '';
  }

  static String _joinDisplay(String resolution, String refreshRate) {
    final hasResolution = _hasValue(resolution);
    final hasRefreshRate = _hasValue(refreshRate);
    if (!hasResolution && !hasRefreshRate) return '';

    final formattedResolution = hasResolution
        ? resolution.replaceAll(RegExp(r'\s*[xX]\s*'), ' × ')
        : '';
    final formattedRefreshRate = hasRefreshRate
        ? refreshRate.replaceAll(' ', '')
        : '';
    if (hasResolution && hasRefreshRate) {
      return '$formattedResolution ($formattedRefreshRate)';
    }
    return hasResolution ? formattedResolution : formattedRefreshRate;
  }

  static bool _hasValue(String value) {
    return value.trim().isNotEmpty && value.trim() != '-';
  }
}

class _MirrorDeviceInfoLoadingCard extends StatelessWidget {
  const _MirrorDeviceInfoLoadingCard({
    required this.deviceName,
    this.showLoading = true,
  });

  final String deviceName;
  final bool showLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            deviceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (showLoading) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.t('reading'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
