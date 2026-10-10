import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/widget/menu_corner_indicator.dart';
import 'package:any_deck/features/overview/widget/service_restart_menu_button.dart';
import 'package:any_deck/features/overview/widget/tool_directory_menu_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MenuCornerIndicator Widget Tests', () {
    testWidgets('renders child icon and corner triangle indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MenuCornerIndicator(
                child: Icon(CupertinoIcons.restart),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MenuCornerIndicator), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.restart), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('inherits size from IconTheme when size is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: IconTheme(
                data: IconThemeData(size: 30, color: Colors.blue),
                child: MenuCornerIndicator(
                  child: Icon(CupertinoIcons.restart),
                ),
              ),
            ),
          ),
        ),
      );

      final sizedBoxFinder = find.descendant(
        of: find.byType(MenuCornerIndicator),
        matching: find.byType(SizedBox),
      ).first;

      final sizedBox = tester.widget<SizedBox>(sizedBoxFinder);
      expect(sizedBox.width, 30);
      expect(sizedBox.height, 30);
    });

    testWidgets('respects explicit size, indicatorSize, and offset', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MenuCornerIndicator(
                size: 32,
                indicatorSize: 8,
                offset: Offset(2, 2),
                indicatorColor: Colors.red,
                child: Icon(CupertinoIcons.restart),
              ),
            ),
          ),
        ),
      );

      final sizedBoxFinder = find.descendant(
        of: find.byType(MenuCornerIndicator),
        matching: find.byType(SizedBox),
      ).first;

      final sizedBox = tester.widget<SizedBox>(sizedBoxFinder);
      expect(sizedBox.width, 32);
      expect(sizedBox.height, 32);

      final positionedFinder = find.descendant(
        of: find.byType(MenuCornerIndicator),
        matching: find.byType(Positioned),
      );
      final positioned = tester.widget<Positioned>(positionedFinder);
      expect(positioned.right, 2);
      expect(positioned.bottom, 2);
      expect(positioned.width, 8);
      expect(positioned.height, 8);
    });

    testWidgets('ServiceRestartMenuButton renders with MenuCornerIndicator', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: [AppLocalizationsDelegate()],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: ServiceRestartMenuButton(
                  iconColor: Colors.grey,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ServiceRestartMenuButton), findsOneWidget);
      expect(find.byType(MenuCornerIndicator), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.restart), findsOneWidget);
    });

    testWidgets('ToolDirectoryMenuButton renders with MenuCornerIndicator', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: [AppLocalizationsDelegate()],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: ToolDirectoryMenuButton(
                  iconColor: Colors.grey,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ToolDirectoryMenuButton), findsOneWidget);
      expect(find.byType(MenuCornerIndicator), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.folder), findsOneWidget);
    });
  });
}
