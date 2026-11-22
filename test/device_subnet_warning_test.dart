import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/common/utils/network_util.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/network/host_network_service.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/features/devices/widgets/device_subnet_warning.dart';
import 'package:any_deck/features/devices/widgets/host_network_footer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用内存快照驱动真实 Provider，不调用原生通道或读取实际网络。
class _HostNetworkService extends HostNetworkService {
  HostNetworkInfo info = _network('192.168.31.105');
  bool fail = false;
  int reads = 0;
  int permissionRequests = 0;

  @override
  Future<void> requestWifiAccess() async {
    permissionRequests++;
  }

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
        final textFields = find.semantics.byPredicate(
          (node) => node.flagsCollection.isTextField,
        );
        // 启动时占位文字会更新为 IP，两帧都应向辅助功能提供文本标签。
        expect(textFields, findsNothing);
        expect(
          find.semantics.byLabel(l10n.t('hostNetworkLoading')),
          findsOneWidget,
        );
        expect(warning, findsNothing);
        await tester.pumpAndSettle();
        expect(textFields, findsNothing);
        expect(find.semantics.byLabel('192.168.31.105'), findsOneWidget);
        expect(warning, findsOneWidget);
        expect(find.byTooltip(l10n.t('deviceSubnetWarning')), findsOneWidget);
        expect(service.reads, 1);

        // 底栏只保留地址，Wi-Fi、网卡和手动刷新统一放在详情。
        expect(find.text('test-wifi'), findsNothing);
        await tester.tap(find.byKey(const Key('hostNetworkDetails')));
        await tester.pumpAndSettle();
        expect(find.text('test-wifi'), findsOneWidget);
        expect(find.text('en0'), findsOneWidget);

        // 相同手机 IP、同一个页面，手动刷新必须丢弃原先的不匹配结果。
        service.info = _network('192.168.0.105');
        await tester.tap(find.text(l10n.t('hostNetworkRefresh')));
        await tester.pumpAndSettle();
        expect(warning, findsNothing);
        expect(find.text('192.168.0.105'), findsNWidgets(2));
        // 详情弹层中的地址、Wi-Fi 和网卡同样需要通过文本标签读出。
        expect(textFields, findsNothing);
        expect(find.semantics.byLabel('192.168.0.105'), findsNWidgets(2));
        expect(find.semantics.byLabel('test-wifi'), findsOneWidget);
        expect(find.semantics.byLabel('en0'), findsOneWidget);
        expect(service.reads, 2);

        // 不再自动轮询：等待 10 秒后不应触发自动刷新。
        service.info = _network('192.168.31.105');
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(warning, findsNothing);
        expect(service.reads, 2);

        // 手动刷新后更新提示与信息。
        await tester.tap(find.text(l10n.t('hostNetworkRefresh')));
        await tester.pumpAndSettle();
        expect(warning, findsOneWidget);
        expect(service.reads, 3);

        service.fail = true;
        await tester.tap(find.text(l10n.t('hostNetworkRefresh')));
        await tester.pumpAndSettle();
        expect(warning, findsNothing);

        service.fail = false;
        service.info = const HostNetworkInfo();
        await tester.tap(find.text(l10n.t('hostNetworkRefresh')));
        await tester.pumpAndSettle();
        expect(warning, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }

  testWidgets('底栏复制实际主机地址，权限读取只在详情显式请求', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _HostNetworkService();
    service.info = const HostNetworkInfo(
      wifiStatus: HostWifiStatus.permissionRequired,
      address: HostNetworkAddress('en0', '192.168.31.105'),
    );
    final clipboardWrites = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardWrites.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hostNetworkServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: const Scaffold(
            body: Column(children: [Spacer(), HostNetworkFooter()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Tab 直接进入复制按钮，拖选文字后仍可以用 ⌘C 复制。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      Focus.of(tester.element(find.byIcon(Icons.copy_outlined))).hasFocus,
      isTrue,
    );

    Future<void> dragAndCopy(Finder text) async {
      final rect = tester.getRect(text);
      await tester.dragFrom(
        rect.centerLeft + const Offset(1, 0),
        Offset(rect.width - 2, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    }

    await dragAndCopy(find.byKey(const Key('hostNetworkAddress')));
    expect(clipboardWrites, ['192.168.31.105']);
    clipboardWrites.clear();
    expect(service.permissionRequests, 0);
    await tester.tap(find.byKey(const Key('copyHostIp')));
    await tester.pumpAndSettle();
    expect(clipboardWrites, ['192.168.31.105']);
    expect(service.permissionRequests, 0);
    expect(find.text('点击授权读取名称'), findsNothing);
    await tester.tap(find.byKey(const Key('hostNetworkDetails')));
    await tester.pumpAndSettle();
    expect(find.text('未授权(需定位权限)'), findsOneWidget);
    final interfaceName = find.text('en0');
    expect(Focus.of(tester.element(interfaceName)).skipTraversal, isTrue);
    clipboardWrites.clear();
    await dragAndCopy(interfaceName);
    expect(clipboardWrites, ['en0']);
    await tester.tap(find.text('点击授权读取名称'));
    await tester.pumpAndSettle();
    expect(service.permissionRequests, 1);
    expect(service.reads, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final locale in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('全局底栏在窄屏和大字号下地址完整可见 $locale $brightness', (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final width in [320.0, 500.0, 1200.0]) {
          tester.view.physicalSize = Size(width, 400);
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey(width),
              overrides: [
                hostNetworkServiceProvider.overrideWithValue(
                  _HostNetworkService(),
                ),
              ],
              child: MaterialApp(
                locale: Locale(locale),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizationsDelegate(),
                  ...GlobalMaterialLocalizations.delegates,
                ],
                theme: ThemeData(brightness: brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.6)),
                  child: child!,
                ),
                home: const Scaffold(
                  body: Column(children: [Spacer(), HostNetworkFooter()]),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final address = find.byKey(const Key('hostNetworkAddress'));
          expect(find.text('192.168.31.105'), findsOneWidget);
          expect(address.hitTestable(), findsOneWidget);
          for (final key in [
            const Key('hostNetworkAddress'),
            const Key('copyHostIp'),
            const Key('hostNetworkDetails'),
            const ValueKey('services-diagnostics-button'),
          ]) {
            final rect = tester.getRect(find.byKey(key));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
