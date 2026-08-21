part of '../dashboard_screen.dart';

/// 单击文件条目时只更新选中态，不触发目录跳转或文件预览。
void _selectRemoteFile(WidgetRef ref, String deviceId, String remotePath) {
  ref.read(fileSelectionProvider.notifier).select(deviceId, remotePath);
}

/// 双击文件条目时执行打开行为：目录进入下级，可预览文件交给系统默认应用。
void _openRemoteFile(
  BuildContext context,
  WidgetRef ref,
  String deviceId,
  String currentPath,
  RemoteFile file,
) {
  final remotePath = _joinRemotePath(currentPath, file.name);
  _selectRemoteFile(ref, deviceId, remotePath);
  if (file.isFolder) {
    ref.read(fileNavigationProvider.notifier).navigateTo(remotePath);
  } else if (FilePreviewController.isPreviewable(file)) {
    unawaited(_previewRemoteFile(context, ref, deviceId, currentPath, file));
  }
}
