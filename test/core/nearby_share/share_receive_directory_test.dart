import 'dart:io';

import 'package:any_deck/app/settings/harmony_share_preference_keys.dart';
import 'package:any_deck/core/nearby_share/share_receive_directory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('默认 Downloads 可注入，自定义目录缺失不回退', () async {
    final root = await Directory.systemTemp.createTemp('share-directory-');
    try {
      expect(
        (await ShareReceiveDirectory.resolvePath(
          '',
          downloads: () async => root,
        ))!.path,
        root.path,
      );
      var fallback = false;
      await expectLater(
        ShareReceiveDirectory.resolvePath(
          '${root.path}/missing',
          downloads: () async {
            fallback = true;
            return root;
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(fallback, isFalse);
      expect(
        () => ShareReceiveDirectory.validatePath('relative'),
        throwsFormatException,
      );
      expect(
        () => ShareReceiveDirectory.validatePath('/bad\u0000path'),
        throwsFormatException,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('显式探测不会修改已有文件，探测目录被清理，服务读取已保存路径', () async {
    final root = await Directory.systemTemp.createTemp('share-directory-');
    try {
      final existing = File('${root.path}/existing');
      await existing.writeAsString('unchanged');
      await ShareReceiveDirectory.checkWritable(root.path);
      expect(await existing.readAsString(), 'unchanged');
      expect(await root.list().length, 1);
      SharedPreferences.setMockInitialValues({
        HarmonySharePreferenceKeys.receiveDirectory: root.path,
      });
      expect((await ShareReceiveDirectory.resolve())!.path, root.path);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
