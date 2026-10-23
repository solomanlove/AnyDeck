import 'package:any_deck/features/overview/widget/receiver_name_setting_field.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DLNA 名称可编辑、提交并恢复默认', (tester) async {
    var currentName = 'AnyDeck DLNA';
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ReceiverNameSettingField(
                value: currentName,
                defaultName: 'AnyDeck DLNA',
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
    expect(currentName, 'AnyDeck DLNA');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'AnyDeck DLNA',
    );
  });
}
