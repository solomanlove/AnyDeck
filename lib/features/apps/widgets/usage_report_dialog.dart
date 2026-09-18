part of '../../dashboard_screen.dart';

/// 使用时长弹窗，通过 showDialog 展示；deviceId 为目标 ADB 路由。
/// 安装与同步由 controller 处理，名称和图标复用应用列表的 _AppNameCell。
class UsageReportDialog extends ConsumerWidget {
  const UsageReportDialog({super.key, required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(
      usageReportViewProvider(deviceId).select((value) => value.tab),
    );
    final viewController = ref.read(usageReportViewProvider(deviceId).notifier);
    final state = ref.watch(usageReportProvider(deviceId));
    final controller = ref.read(usageReportProvider(deviceId).notifier);
    final online = ref.watch(deviceOnlineProvider(deviceId));
    final packages =
        ref.watch(packagesProvider(deviceId)).value ?? <AdbPackage>[];
    final byName = {for (final package in packages) package.name: package};
    final colors = Theme.of(context).colorScheme;
    final snapshot = state.snapshot;
    final enabled = online && !state.busy;
    return AlertDialog(
      title: Text(context.l10n.t('usageTitle')),
      content: SizedBox(
        width: 820,
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n.t('usageIntro')),
            const SizedBox(height: 12),
            if (tab < 2)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: enabled ? controller.install : null,
                    child: Text(context.l10n.t('usageInstall')),
                  ),
                  OutlinedButton(
                    onPressed: enabled ? controller.open : null,
                    child: Text(context.l10n.t('usageOpen')),
                  ),
                  FilledButton.icon(
                    onPressed: enabled
                        ? (tab == 0
                              ? controller.sync
                              : controller.syncLocations)
                        : null,
                    icon: const Icon(
                      CupertinoIcons.arrow_2_circlepath,
                      size: 16,
                    ),
                    label: Text(
                      context.l10n.t(tab == 0 ? 'usageSync' : 'locationSync'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            if (tab < 2 && state.busy) const LinearProgressIndicator(),
            if (tab < 2 && state.messageKey != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.l10n.t(state.messageKey!),
                  style: TextStyle(
                    color: state.failed ? colors.error : colors.primary,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text(context.l10n.t('usageTitle')),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text(context.l10n.t('locationTitle')),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text(context.l10n.t('cameraTitle')),
                ),
                ButtonSegment(
                  value: 3,
                  label: Text(context.l10n.t('clipboardTitle')),
                ),
              ],
              selected: {tab},
              onSelectionChanged: (value) =>
                  viewController.selectTab(value.first),
            ),
            if (tab < 2 && state.history.hasGap)
              Text(
                context.l10n.t('historyGap'),
                style: TextStyle(color: colors.error),
              ),
            if (tab == 0 && state.history.usage.isNotEmpty)
              DropdownButton<UsageSnapshot>(
                isExpanded: true,
                value: snapshot,
                items: state.history.usage
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(
                          DateTime.fromMillisecondsSinceEpoch(
                                item.requestedStartMs,
                                isUtc: true,
                              )
                              .add(Duration(minutes: item.utcOffsetMinutes))
                              .toIso8601String()
                              .split('T')
                              .first,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: state.busy
                    ? null
                    : (value) {
                        if (value != null) controller.selectSnapshot(value);
                      },
              ),
            Expanded(
              child: tab == 3
                  ? DeviceClipboardView(deviceId: deviceId)
                  : tab == 2
                  ? CameraPreviewView(deviceId: deviceId)
                  : tab == 1
                  ? LocationHistoryView(
                      deviceId: deviceId,
                      history: state.history,
                    )
                  : snapshot == null
                  ? Center(child: Text(context.l10n.t('usageEmpty')))
                  : _UsageSnapshotView(
                      deviceId: deviceId,
                      snapshot: snapshot,
                      packages: byName,
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (snapshot != null || state.history.locations.isNotEmpty)
          TextButton(
            onPressed: state.busy ? null : controller.clear,
            child: Text(context.l10n.t('usageClear')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.t('close')),
        ),
      ],
    );
  }
}

/// 快照内容使用虚拟列表；包展示数据由已有 packagesProvider 提供。
class _UsageSnapshotView extends StatelessWidget {
  const _UsageSnapshotView({
    required this.deviceId,
    required this.snapshot,
    required this.packages,
  });
  final String deviceId;
  final UsageSnapshot snapshot;
  final Map<String, AdbPackage> packages;

  String _duration(int milliseconds) =>
      Duration(milliseconds: milliseconds).toString().split('.').first;

  // 以快照记录的手机 UTC offset 展示，避免电脑时区改变查询日期。
  String _time(int milliseconds) =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true)
          .add(Duration(minutes: snapshot.utcOffsetMinutes))
          .toIso8601String()
          .replaceFirst('T', ' ')
          .split('.')
          .first;

  String _range(int start, int end) => '${_time(start)} — ${_time(end)}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: snapshot.apps.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.t('usageCachedNote'),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(
                  '${context.l10n.t('usageSnapshotTime')}: ${_time(snapshot.generatedAtMs)}',
                ),
                Text(
                  '${context.l10n.t('usageDeviceTime')}: ${snapshot.timeZone}',
                ),
                Text(
                  '${context.l10n.t('usageAndroidUser')}: ${snapshot.androidUserId}',
                ),
                const SizedBox(height: 8),
                Text(
                  '${context.l10n.t('usageScreen')}: '
                  '${snapshot.screenInteractiveMs == null ? context.l10n.t('usageUnavailable') : _duration(snapshot.screenInteractiveMs!)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (snapshot.screenRangeStartMs != null)
                  Text(
                    '${context.l10n.t('usageRange')}: '
                    '${_range(snapshot.screenRangeStartMs!, snapshot.screenRangeEndMs!)}',
                  ),
                const SizedBox(height: 8),
                Text(
                  '${context.l10n.t('usageCombined')}: ${_duration(snapshot.combinedForegroundMs)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${context.l10n.t('usageRange')}: '
                  '${_range(snapshot.rangeStartMs, snapshot.rangeEndMs)}',
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.t('usageBucketNote'),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const Divider(),
                if (snapshot.apps.isEmpty) Text(context.l10n.t('usageNoApps')),
              ],
            ),
          );
        }
        final app = snapshot.apps[index - 1];
        return Tooltip(
          message: _range(app.rangeStartMs, app.rangeEndMs),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _AppNameCell(
                    deviceId: deviceId,
                    package:
                        packages[app.packageName] ??
                        AdbPackage(name: app.packageName),
                  ),
                ),
                const SizedBox(width: 16),
                Text(_duration(app.foregroundMs)),
              ],
            ),
          ),
        );
      },
    );
  }
}
