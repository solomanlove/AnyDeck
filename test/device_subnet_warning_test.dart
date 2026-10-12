import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/common/utils/network_util.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/network/host_network_service.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/features/devices/widgets/device_subnet_warning.dart';
import 'package:any_deck/features/devices/widgets/host_network_footer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用内存快照驱动真实 Provider，不调用原生通道或读取实际网络。
class _HostNetworkService extends HostNetworkService {
  HostNetworkInfo info = _network('192.168.31.105');
  bool fail = false;
  int reads = 0;

  @override
  Future<HostNetworkInfo> read() async {
    reads++;
    if (fail) throw StateError('网络读取失败');
    return info;
  }
}

HostNetworkInfo _network(String ip) => HostNetworkInfo.resolve(
  {
    'wifiInterfaces': [
      {'name': 'en0', 'connected': true, 'ssid': 'test-wifi'},
    ],
    'physicalInterfaces': ['en0'],
  },
  [HostNetworkAddress('en0', ip)],
);

void main() {
  test('截图中的手机与电脑 IPv4 不应触发网段警告', () {
    expect(
      NetworkLanMatcher.matchesAnySubnet('192.168.0.104', ['192.168.0.105']),
      isTrue,
    );
    expect(
      NetworkLanMatcher.matchesAnySubnet('192.168.31.153', ['192.168.0.105']),
      isFalse,
    );
  });

  test('保留已有私有地址估算规则', () {
    for (final pair in [
      ['10.1.2.3', '10.2.3.4'],
      ['172.16.1.2', '172.31.2.3'],
    ]) {
      expect(NetworkLanMatcher.matchesAnySubnet(pair[0], [pair[1]]), isTrue);
    }
    expect(
      NetworkLanMatcher.matchesAnySubnet('172.16.1.2', ['172.32.1.2']),
      isFalse,
    );
  });

  test('未知、无效或非局域网地址不作为不匹配证据', () {
    for (final ip in [
      '',
      '-',
      '192.168.0.999',
      '127.0.0.1',
      '169.254.1.2',
      '::1',
    ]) {
      expect(NetworkLanMatcher.matchesAnySubnet(ip, ['192.168.0.105']), isNull);
      expect(NetworkLanMatcher.matchesAnySubnet('192.168.0.104', [ip]), isNull);
    }
    expect(NetworkLanMatcher.matchesAnySubnet('192.168.0.104', []), isNull);
  });

  test('快照保留全部有效网卡，任一网卡匹配即不提示', () {
    final info = HostNetworkInfo.resolve(null, const [
      HostNetworkAddress('en0', '192.168.31.105'),
      HostNetworkAddress('en1', '192.168.0.105'),
      HostNetworkAddress('lo0', '127.0.0.1'),
    ]);
    expect(info.address?.ipv4, '192.168.31.105');
    expect(info.ipv4Addresses, hasLength(2));
    expect(
      NetworkLanMatcher.matchesAnySubnet(
        '192.168.0.104',
        info.ipv4Addresses.map((entry) => entry.ipv4),
      ),
      isTrue,
    );
  });

  for (final locale in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('底栏手动刷新同步更新提示 $locale $brightness', (tester) async {
        final service = _HostNetworkService();
        final l10n = AppLocalizations(Locale(locale));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [hostNetworkServiceProvider.overrideWithValue(service)],
            child: MaterialApp(
              locale: Locale(locale),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                ...GlobalMaterialLocalizations.delegates,
              ],
              theme: ThemeData(brightness: brightness),
              home: const Scaffold(
                body: Column(
                  children: [
                    DeviceSubnetWarning(wifiIp: '192.168.0.104'),
                    HostNetworkFooter(),
                  ],
                ),
              ),
            ),
          ),
        );
        final warning = find.byIcon(CupertinoIcons.exclamationmark_circle_fill);
        expect(warning, findsNothing);
        await tester.pumpAndSettle();
        expect(warning, findsOneWidget);
        expect(find.byTooltip(l10n.t('deviceSubnetWarning')), findsOneWidget);
        expect(service.reads, 1);

        // 相同手机 IP、同一个页面，手动刷新必须丢弃原先的不匹配结果。
        service.info = _network('192.168.0.105');
        await tester.tap(find.byTooltip(l10n.t('hostNetworkRefresh')));
        await tester.pumpAndSettle();
        expect(warning, findsNothing);
        expect(find.text('IP: 192.168.0.105 (en0)'), findsOneWidget);
        expect(service.reads, 2);

        // 不再自动轮询：等待 10 秒后不应触发自动刷新。
        service.info = _network('192.168.31.105');
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(warning, findsNothing);
        expect(service.reads, 2);

        // 手动刷新后更新提示与信息。
        await tester.tap(find.byTooltip(l10n.t('hostNetworkRefresh')));
        await tester.pumpAndSettle();
        expect(warning, findsOneWidget);
        expect(service.reads, 3);

        service.fail = true;
        await tester.tap(find.byTooltip(l10n.t('hostNetworkRefresh')));
        await tester.pumpAndSettle();
        expect(warning, findsNothing);

        service.fail = false;
        service.info = const HostNetworkInfo();
        await tester.tap(find.byTooltip(l10n.t('hostNetworkRefresh')));
        await tester.pumpAndSettle();
        expect(warning, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
