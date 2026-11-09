import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:any_deck/core/mcp/mcp_server.dart';

/// 显式启用的真机只读回归，不安装、卸载、输入或清数据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '在线设备发现、实时概览、截图和平台应用读取',
    () async {
      SharedPreferences.setMockInitialValues({});
      final registry = McpServer.createDefaultRegistry();
      final found = await registry.executeTool(
        name: 'list_devices',
        arguments: {'forceRefresh': true},
      );
      final online = (found['devices'] as List)
          .where((d) => d['isOnline'] == true)
          .toList();
      expect(online, isNotEmpty, reason: '需要至少一台已授权的真机');
      final platforms = <String>[];
      for (final d in online) {
        final platform = d['platform'] as String;
        final id = d['id'] as String;
        Future<Map<String, dynamic>> call(
          String name, [
          Map<String, dynamic> args = const {},
        ]) => registry.executeTool(
          name: name,
          arguments: {'deviceId': id, ...args},
          platform: platform,
        );
        final detail = await call('get_device_detail');
        expect(detail['dataSource'], 'live');
        final screenshot = await call('take_screenshot');
        expect(screenshot['width'], greaterThan(0));
        expect(screenshot['height'], greaterThan(0));
        expect(screenshot['base64'], isNotEmpty);
        if (platform == 'ios') {
          expect((await call('ios_list_apps'))['apps'], isA<List>());
        } else {
          expect(
            (await call('list_installed_apps', {'forceRefresh': true}))['apps'],
            isA<List>(),
          );
        }
        if (platform == 'harmony') {
          expect((await call('query_hilog'))['logs'], isA<List>());
        }
        platforms.add(platform);
      }
      // 仅输出验证平台数量，不向 CI 日志输出 UDID、画面或应用清单。
      // ignore: avoid_print
      print('Read-only device smoke platforms: ${platforms.join(', ')}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: Platform.environment['ANYDECK_MCP_DEVICE_SMOKE'] != '1'
        ? '设置 ANYDECK_MCP_DEVICE_SMOKE=1 后使用已授权设备运行'
        : false,
  );
}
