import 'dart:async';

import 'package:any_deck/features/overview/widget/receiver_name_setting_field.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DLNA 名称可编辑、提交并恢复默认', (tester) async {
    const defaultName = 'AnyDeck-办公室Mac-DLNA';
    var currentName = defaultName;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ReceiverNameSettingField(
                value: currentName,
                defaultName: defaultName,
                resetTooltip: '恢复默认',
                onChanged: (value) => setState(() => currentName = value),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '  客厅电视  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(currentName, '客厅电视');
    expect(find.text('客厅电视'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.refresh));
    await tester.pump();
    expect(currentName, defaultName);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      defaultName,
    );
  });

  testWidgets('名称保存完成后再更新广播，提交与失焦不会重复保存', (tester) async {
    final saved = Completer<void>();
    final events = <String>[];
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ReceiverNameSettingField(
            value: 'AnyDeck-办公室Mac-AirPlay',
            defaultName: 'AnyDeck-办公室Mac-AirPlay',
            resetTooltip: '恢复本机默认名称',
            onChanged: (name) async {
              events.add('saving:$name');
              await saved.future;
              events.add('saved');
            },
            onApplied: (_, name) => events.add('broadcast:$name'),
          ),
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), '会议室Mac');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(events, ['saving:会议室Mac']);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    saved.complete();
    await tester.pump();
    expect(events, ['saving:会议室Mac', 'saved', 'broadcast:会议室Mac']);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
