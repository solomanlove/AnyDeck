part of '../dashboard_screen.dart';

/// 单击文件条目时只更新选中态，不触发目录跳转或文件预览。
void _selectRemoteFile(WidgetRef ref, String deviceId, String remotePath) {
  ref.read(fileSelectionProvider.notifier).select(deviceId, remotePath);
}

/// 双击文件条目时执行原有打开行为：目录进入下级，文本文件打开预览。
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
  } else if (_isPreviewableTextFile(file.name)) {
    _previewTextFile(context, ref, deviceId, currentPath, file);
  }
}
