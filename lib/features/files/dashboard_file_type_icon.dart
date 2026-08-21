part of '../dashboard_screen.dart';

enum _RemoteFileIconKind {
  folder,
  link,
  image,
  video,
  audio,
  pdf,
  document,
  spreadsheet,
  presentation,
  archive,
  androidPackage,
  code,
  file,
}

/// 根据远程条目类型和文件扩展名选择 icon，扩展名匹配不区分大小写。
_RemoteFileIconKind _fileIconKind(RemoteFile file) {
  if (file.isFolder) return _RemoteFileIconKind.folder;
  if (file.isLink) return _RemoteFileIconKind.link;

  final dotIndex = file.name.lastIndexOf('.');
  final extension = dotIndex < 0
      ? ''
      : file.name.substring(dotIndex + 1).toLowerCase();

  if (_imageExtensions.contains(extension)) return _RemoteFileIconKind.image;
  if (_videoExtensions.contains(extension)) return _RemoteFileIconKind.video;
  if (_audioExtensions.contains(extension)) return _RemoteFileIconKind.audio;
  if (extension == 'pdf') return _RemoteFileIconKind.pdf;
  if (_spreadsheetExtensions.contains(extension)) {
    return _RemoteFileIconKind.spreadsheet;
  }
  if (_presentationExtensions.contains(extension)) {
    return _RemoteFileIconKind.presentation;
  }
  if (_documentExtensions.contains(extension)) {
    return _RemoteFileIconKind.document;
  }
  if (_androidPackageExtensions.contains(extension)) {
    return _RemoteFileIconKind.androidPackage;
  }
  if (_archiveExtensions.contains(extension)) {
    return _RemoteFileIconKind.archive;
  }
  if (_codeExtensions.contains(extension)) return _RemoteFileIconKind.code;
  return _RemoteFileIconKind.file;
}

IconData _fileIcon(RemoteFile file) {
  return switch (_fileIconKind(file)) {
    _RemoteFileIconKind.folder => Icons.folder_rounded,
    _RemoteFileIconKind.link => Icons.link_rounded,
    _RemoteFileIconKind.image => Icons.image_rounded,
    _RemoteFileIconKind.video => Icons.movie_rounded,
    _RemoteFileIconKind.audio => Icons.audio_file_rounded,
    _RemoteFileIconKind.pdf => Icons.picture_as_pdf_rounded,
    _RemoteFileIconKind.document => Icons.description_rounded,
    _RemoteFileIconKind.spreadsheet => Icons.table_chart_rounded,
    _RemoteFileIconKind.presentation => Icons.slideshow_rounded,
    _RemoteFileIconKind.archive => Icons.archive_rounded,
    _RemoteFileIconKind.androidPackage => Icons.android_rounded,
    _RemoteFileIconKind.code => Icons.code_rounded,
    _RemoteFileIconKind.file => Icons.insert_drive_file_rounded,
  };
}

/// 使用 ColorScheme 的语义色，确保 Light/Dark mode 下都有足够辨识度。
Color _fileIconColor(BuildContext context, RemoteFile file) {
  final colors = Theme.of(context).colorScheme;
  return switch (_fileIconKind(file)) {
    _RemoteFileIconKind.folder => Colors.amber.shade700,
    _RemoteFileIconKind.link => colors.tertiary,
    _RemoteFileIconKind.image => colors.tertiary,
    _RemoteFileIconKind.video => colors.error,
    _RemoteFileIconKind.audio => colors.primary,
    _RemoteFileIconKind.pdf => colors.error,
    _RemoteFileIconKind.document => colors.primary,
    _RemoteFileIconKind.spreadsheet => colors.tertiary,
    _RemoteFileIconKind.presentation => colors.secondary,
    _RemoteFileIconKind.archive => colors.secondary,
    _RemoteFileIconKind.androidPackage => colors.tertiary,
    _RemoteFileIconKind.code => colors.primary,
    _RemoteFileIconKind.file => colors.onSurfaceVariant,
  };
}

const _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
  'svg',
};
const _videoExtensions = {
  'mp4',
  'mkv',
  'mov',
  'avi',
  'webm',
  'm4v',
  '3gp',
  'flv',
};
const _audioExtensions = {
  'mp3',
  'wav',
  'flac',
  'm4a',
  'aac',
  'ogg',
  'opus',
  'amr',
};
const _documentExtensions = {
  'txt',
  'md',
  'log',
  'rtf',
  'doc',
  'docx',
  'odt',
  'json',
  'xml',
  'yaml',
  'yml',
};
const _spreadsheetExtensions = {'xls', 'xlsx', 'ods', 'csv', 'tsv'};
const _presentationExtensions = {'ppt', 'pptx', 'odp'};
const _androidPackageExtensions = {'apk', 'apks', 'xapk', 'aab'};
const _archiveExtensions = {
  'zip',
  'rar',
  '7z',
  'tar',
  'gz',
  'bz2',
  'xz',
  'tgz',
  'jar',
};
const _codeExtensions = {
  'dart',
  'kt',
  'kts',
  'java',
  'swift',
  'js',
  'jsx',
  'ts',
  'tsx',
  'py',
  'sh',
  'c',
  'cc',
  'cpp',
  'h',
  'hpp',
  'html',
  'css',
  'scss',
  'sql',
  'gradle',
};
