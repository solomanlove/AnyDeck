import 'package:any_deck/app/theme/app_navigation_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('设备侧栏图标使用同一字体且每个入口拥有独立图形', (tester) async {
    const icons = <IconData>[
      AppNavigationIcons.overview,
      AppNavigationIcons.control,
      AppNavigationIcons.apps,
      AppNavigationIcons.processes,
      AppNavigationIcons.files,
      AppNavigationIcons.logs,
      AppNavigationIcons.terminal,
      AppNavigationIcons.web,
      AppNavigationIcons.layout,
      AppNavigationIcons.capture,
      AppNavigationIcons.performance,
      AppNavigationIcons.network,
    ];

    expect(icons.toSet(), hasLength(icons.length));
    expect(icons.every((icon) => icon.fontFamily == 'Lucide'), isTrue);
    expect(
      icons.every((icon) => icon.fontPackage == 'lucide_icons_flutter'),
      isTrue,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(children: [for (final icon in icons) Icon(icon)]),
        ),
      ),
    );
    expect(find.byType(Icon), findsNWidgets(icons.length));
    expect(tester.takeException(), isNull);
  });
}
