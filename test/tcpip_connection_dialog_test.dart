import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/network/network_device_address.dart';
import 'package:any_deck/features/devices/widgets/tcpip_connection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('地址校验拒绝无效端口、命令及错误 IP，保留合法地址', () {
    for (final invalid in [
      '',
      'invalid:abc',
      '1.2.3.4:0',
      '1.2.3.4:65536',
      '999.2.3.4',
      'adb connect 1.2.3.4',
      'host/path',
      'x;reboot:5555',
    ]) {
      expect(NetworkDeviceAddress.tryParse(invalid), isNull, reason: invalid);
    }
    expect(
      NetworkDeviceAddress.tryParse(' 192.168.31.33 ')?.address,
      '192.168.31.33:5555',
    );
    expect(
      NetworkDeviceAddress.tryParse('phone.local:1234')?.address,
      'phone.local:1234',
    );
    expect(NetworkDeviceAddress.tryParse('[::1]:5555')?.host, '::1');
  });

  for (final locale in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('$locale $brightness 无效输入留在表单，成功退出不提前释放控制器', (tester) async {
        final addresses = <String>[];
        await _open(
          tester,
          locale: locale,
          brightness: brightness,
          connect: (value) async {
            addresses.add(value);
            return const AdbResult(
              exitCode: 0,
              stdout: 'connected',
              stderr: '',
            );
          },
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField))
              .controller!
              .text,
          isEmpty,
        );
        final l10n = AppLocalizations(Locale(locale));
        expect(find.text(l10n.t('tcpipPrepareTitle')), findsNothing);
        await tester.enterText(find.byType(TextFormField), 'invalid:abc');
        await tester.tap(find.widgetWithText(FilledButton, l10n.t('connect')));
        await tester.pumpAndSettle();
        expect(addresses, isEmpty);
        expect(find.text(l10n.t('tcpipInvalidAddress')), findsOneWidget);
        await tester.enterText(
          find.byType(TextFormField),
          '192.168.31.33:5555',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(addresses, ['192.168.31.33:5555']);
        expect(find.byType(TcpipConnectionDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('连接失败保留输入可重试，等待时不重复提交', (tester) async {
    var calls = 0;
    final pending = Completer<AdbResult>();
    await _open(
      tester,
      connect: (_) {
        calls++;
        return pending.future;
      },
    );
    await tester.enterText(find.byType(TextFormField), '192.168.31.33:5555');
    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.complete(
      const AdbResult(exitCode: 1, stdout: '', stderr: 'device offline'),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('device offline'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '192.168.31.33:5555',
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('等待连接期间关闭弹窗，晚到结果不操作已销毁界面', (tester) async {
    final pending = Completer<AdbResult>();
    await _open(tester, connect: (_) => pending.future);
    await tester.enterText(find.byType(TextFormField), '192.168.31.33:5555');
    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    pending.completeError(StateError('late failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _open(
  WidgetTester tester, {
  String locale = 'zh',
  Brightness brightness = Brightness.light,
  required Future<AdbResult> Function(String) connect,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: ThemeData(brightness: brightness),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<AdbResult>(
              context: context,
              builder: (_) => TcpipConnectionDialog(connect: connect),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
