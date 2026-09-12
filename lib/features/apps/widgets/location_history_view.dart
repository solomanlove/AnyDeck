import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/usage/companion_database.dart';
import '../../../core/usage/companion_history.dart';
import '../controller/usage_report_view_controller.dart';
import 'location_trail_view.dart';

/// 查看已同步位置；history 是本地数据，不自动请求手机定位或网络地图。
class LocationHistoryView extends ConsumerWidget {
  const LocationHistoryView({
    super.key,
    required this.deviceId,
    required this.history,
  });
  final String deviceId;
  final CompanionHistoryView history;
  String _time(int ms) => DateTime.fromMillisecondsSinceEpoch(
    ms,
  ).toIso8601String().replaceFirst('T', ' ').split('.').first;
  String _date(LocationRecord point) =>
      _time(point.capturedAtMs).split(' ').first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(usageReportViewProvider(deviceId));
    final controller = ref.read(usageReportViewProvider(deviceId).notifier);
    final all = history.locations;
    if (all.isEmpty) {
      return Center(child: Text(context.l10n.t('locationEmpty')));
    }
    final days = all.map(_date).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final day = days.contains(view.day) ? view.day! : days.first;
    final points = all.where((point) => _date(point) == day).toList()
      ..sort((a, b) => b.capturedAtMs.compareTo(a.capturedAtMs));
    final latest = all.reduce(
      (a, b) => a.capturedAtMs >= b.capturedAtMs ? a : b,
    );
    return ListView.builder(
      itemCount: points.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(context.l10n.t('locationCachedNote')),
              Text(
                '${context.l10n.t('locationLatest')}: ${_time(latest.capturedAtMs)}',
              ),
              SelectableText(
                '${latest.latitude.toStringAsFixed(6)}, ${latest.longitude.toStringAsFixed(6)}',
              ),
              if (latest.mock) Text(context.l10n.t('locationMock')),
              Text(
                '${context.l10n.t('usageAndroidUser')}: ${history.source?.androidUserId ?? '-'}',
              ),
              DropdownButton<String>(
                value: day,
                isExpanded: true,
                items: days
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: controller.selectDay,
              ),
              Text(context.l10n.t('locationTrailNote')),
              SizedBox(
                height: 200,
                width: double.infinity,
                child: LocationTrailView(points: points),
              ),
              const Divider(),
            ],
          );
        }
        final point = points[index - 1];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_time(point.capturedAtMs)),
          subtitle: Text(
            '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}\n'
            '${context.l10n.t('locationAccuracy')}: ${point.accuracyMeters.toStringAsFixed(0)} m · ${point.provider}'
            '${point.mock ? ' · ${context.l10n.t('locationMock')}' : ''}',
          ),
          trailing: IconButton(
            tooltip: context.l10n.t('locationMap'),
            onPressed: view.openingMap
                ? null
                : () async {
                    final success = await controller.openMap(point);
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.t('locationMapFailed')),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.map_outlined),
          ),
        );
      },
    );
  }
}
