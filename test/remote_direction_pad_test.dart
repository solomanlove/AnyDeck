import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/widgets/remote_direction_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('四个扇区及中心 OK 各发送对应的方向键码', (tester) async {
    final pressedKeys = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizationsDelegate()],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: RemoteDirectionPad(
              onKey: (key) async {
                pressedKeys.add(key);
              },
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(RemoteDirectionPad));
    for (final offset in [
      const Offset(0, -68),
      const Offset(0, 68),
      const Offset(-68, 0),
      const Offset(68, 0),
      Offset.zero,
    ]) {
      await tester.tapAt(center + offset);
      await tester.pump();
    }

    await tester.tapAt(center + const Offset(90, 90));
    await tester.pump();

    expect(pressedKeys, [19, 20, 21, 22, 23]);
  });
}
