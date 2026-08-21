import 'package:flutter_test/flutter_test.dart';

import 'package:any_deck/core/files/remote_file.dart';
import 'package:any_deck/features/files/controller/file_preview_controller.dart';

void main() {
  group('FilePreviewController.isPreviewable', () {
    test('支持的扩展名不区分大小写', () {
      const file = RemoteFile(name: 'PHOTO.JPEG', type: RemoteFileType.file);

      expect(FilePreviewController.isPreviewable(file), isTrue);
    });

    test('目录和未知扩展名不进入预览链路', () {
      const folder = RemoteFile(name: 'Pictures', type: RemoteFileType.folder);
      const unknown = RemoteFile(
        name: 'archive.unknown',
        type: RemoteFileType.file,
      );

      expect(FilePreviewController.isPreviewable(folder), isFalse);
      expect(FilePreviewController.isPreviewable(unknown), isFalse);
    });
  });
}
