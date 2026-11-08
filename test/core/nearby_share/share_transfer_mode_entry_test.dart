import 'package:any_deck/app/settings/harmony_share_preference_keys.dart';
import 'package:any_deck/core/nearby_share/share_transfer_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 产品入口关闭后，历史配置不能启动 P2P；内部实验配置仍保留。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final saved in [null, false, true]) {
    test('产品接收固定 LAN，保留历史配置 $saved', () async {
      SharedPreferences.setMockInitialValues({
        HarmonySharePreferenceKeys.directMode: ?saved,
      });
      expect(await ShareTransferMode.resolveForApp(), isFalse);
      expect(await ShareTransferMode.resolve(), saved ?? false);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          HarmonySharePreferenceKeys.directMode,
        ),
        saved,
      );
    });
  }
}
