import 'package:any_deck/core/device_share/device_share_invitation.dart';
import 'package:any_deck/core/device_share/device_share_models.dart';
import 'package:any_deck/core/device_share/device_share_service.dart';
import 'package:any_deck/core/device_share/device_share_store.dart';
import 'package:any_deck/core/device_share/hosted_device_share.dart';
import 'package:any_deck/core/device_share/joined_device_share.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/features/devices/widgets/device_share_controls.dart';
import 'package:any_deck/features/devices/widgets/device_share_dialog.dart';
import 'package:any_deck/features/devices/widgets/device_share_saved_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adb_service.dart';
import 'support/device_context_menu_fixture.dart';

/// 记录界面请求，不连接网络；真实连接与持久化由独立集成测试覆盖。
class _Actions extends DeviceShareService {
  _Actions(MemoryDeviceShareStore store)
    : super(FakeAdbService(), store: store);
  String? reconnected, selectedWifi;
  DeviceShareLifetime? selectedLifetime;
  @override
  Future<JoinedDeviceShare> reconnect(String id) async {
    reconnected = id;
    throw StateError('Test sharing is not prepared');
  }

  @override
  Future<HostedDeviceShare> share(
    String deviceId,
    String name,
    String host, {
    DeviceShareLifetime lifetime = DeviceShareLifetime.minutes30,
    String? wifiSsid,
    String? serial,
  }) async {
    selectedLifetime = lifetime;
    selectedWifi = wifiSsid;
    throw StateError('Test network operation');
  }
}

const _network = HostNetworkInfo(
  ssid: 'Test Office',
  verifiedWifiSsid: 'Test Office',
  isWifiAddress: true,
  address: HostNetworkAddress('en0', '192.0.2.10'),
);

Future<void> _open(WidgetTester tester, {bool local = false}) async {
  showDialog<void>(
    context: tester.element(find.byType(DeviceShareControls).first),
    builder: (_) => DeviceShareDialog(device: local ? deviceMenuAndroid : null),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final (language, brightness) in [
    ('zh', Brightness.light),
    ('en', Brightness.dark),
  ]) {
    testWidgets('历史重连、删除与凭据隐藏 $language', (tester) async {
      final invitation = DeviceShareInvitation(
        host: '192.0.2.1',
        port: 54321,
        fingerprint: 'a' * 64,
        token: DeviceShareInvitation.createToken(),
        name: '历史测试手机',
        resumable: true,
      );
      final store = MemoryDeviceShareStore()
        ..value = DeviceShareSavedState(
          history: [
            DeviceShareHistoryEntry(invitation, DateTime.utc(2026, 11, 9)),
          ],
        );
      final actions = _Actions(store);
      await withDeviceMenu(
        tester,
        (fixture) async {
          await _open(tester);
          expect(find.byType(DeviceShareHistoryCard), findsOneWidget);
          expect(find.text('历史测试手机'), findsOneWidget);
          expect(find.textContaining(invitation.token), findsNothing);
          await tester.tap(find.text(language == 'zh' ? '重连' : 'Reconnect'));
          await tester.pumpAndSettle();
          expect(actions.reconnected, invitation.fingerprint);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          await tester.tap(
            find.byTooltip(
              language == 'zh' ? '移除历史记录' : 'Remove history entry',
            ),
          );
          await tester.pumpAndSettle();
          expect(actions.history, isEmpty);
          expect(find.byType(DeviceShareHistoryCard), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(language == 'zh' ? '关闭' : 'Close').last);
          await tester.pumpAndSettle();
        },
        sharing: actions,
        language: language,
        brightness: brightness,
      );
      await actions.dispose();
    });
  }

  for (final (label, lifetime) in [
    ('1 小时', DeviceShareLifetime.hour1),
    ('永久', DeviceShareLifetime.unlimited),
  ]) {
    testWidgets('开始共享使用选择的时长 $label，并保存当前 Wi-Fi 自动规则', (tester) async {
      final actions = _Actions(MemoryDeviceShareStore());
      await withDeviceMenu(
        tester,
        (fixture) async {
          await _open(tester, local: true);
          expect(find.text('30 分钟（推荐）'), findsOneWidget);
          final dropdown = find.byType(
            DropdownButtonFormField<DeviceShareLifetime>,
          );
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(SwitchListTile));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, '开始共享'));
          await tester.pumpAndSettle();
          expect(actions.selectedLifetime, lifetime);
          expect(actions.selectedWifi, 'Test Office');
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('关闭').last);
          await tester.pumpAndSettle();
        },
        sharing: actions,
        network: _network,
      );
      await actions.dispose();
    });
  }
}
