import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/diagnostics/service_diagnostic.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/features/devices/widgets/host_network_footer.dart';
import 'package:any_deck/features/diagnostics/controller/service_diagnostics_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 只发布内存网络快照，不读取宿主网络。
class _Network extends HostNetworkNotifier {
  @override
  Future<HostNetworkInfo> build() async => const HostNetworkInfo(
    address: HostNetworkAddress('en0', '192.168.1.100'),
  );

  void clearAddress() => state = const AsyncData(HostNetworkInfo());
}

/// 驱动检查中与异常徽标，不运行实际诊断探针。
class _Diagnostics extends ServiceDiagnosticsController {
  @override
  ServiceDiagnosticsState build() => ServiceDiagnosticsState.initial();

  void setChecking() =>
      state = const ServiceDiagnosticsState(entries: [], isChecking: true);

  void setIssue() => state = const ServiceDiagnosticsState(
    entries: [
      ServiceDiagnostic(
        service: DiagnosticService.adb,
        status: ServiceDiagnosticStatus.missing,
      ),
    ],
  );
}

/// 读取最终 RichText 样式，包含按钮与 IconTheme 的实际继承结果。
Color? _paintedTextColor(WidgetTester tester, Finder parent) => tester
    .widget<RichText>(
      find.descendant(of: parent, matching: find.byType(RichText)),
    )
    .text
    .style
    ?.color;

void main() {
  for (final brightness in Brightness.values) {
    for (final workspace in [false, true]) {
      for (final width in [320.0, 1200.0]) {
        testWidgets('底栏前景色统一 ${brightness.name} $workspace $width', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 500);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final language = width == 320 ? 'en' : 'zh';
          final l10n = AppLocalizations(Locale(language));
          final base = buildAppTheme(
            brightness,
            themeColor: AppThemeColor.blue,
          );
          final theme = workspace ? buildDeviceWorkspaceTheme(base) : base;
          final container = ProviderContainer(
            overrides: [
              hostNetworkProvider.overrideWith(_Network.new),
              serviceDiagnosticsProvider.overrideWith(_Diagnostics.new),
            ],
          );
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: theme,
                locale: Locale(language),
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
          final foreground = theme.colorScheme.onSurfaceVariant;
          for (final key in [
            'deviceWorkspaceNetworkDetails',
            'diagnosticsTitle',
          ]) {
            expect(
              _paintedTextColor(tester, find.text(l10n.t(key))),
              foreground,
            );
          }
          final address = find.descendant(
            of: find.byKey(const Key('hostNetworkAddress')),
            matching: find.byType(EditableText),
          );
          expect(tester.widget<EditableText>(address).style.color, foreground);
          final icons = [
            Icons.laptop_mac_outlined,
            Icons.copy_outlined,
            Icons.keyboard_arrow_up,
            LucideIcons.activity,
            if (width == 320) Icons.article_outlined,
          ];
          for (final icon in icons) {
            expect(_paintedTextColor(tester, find.byIcon(icon)), foreground);
          }

          final diagnostics =
              container.read(serviceDiagnosticsProvider.notifier)
                  as _Diagnostics;
          diagnostics.setChecking();
          await tester.pump();
          expect(
            tester
                .widget<CircularProgressIndicator>(
                  find.byType(CircularProgressIndicator),
                )
                .color,
            foreground,
          );
          diagnostics.setIssue();
          await tester.pumpAndSettle();
          expect(
            _paintedTextColor(tester, find.text('1')),
            theme.colorScheme.onErrorContainer,
          );
          (container.read(hostNetworkProvider.notifier) as _Network)
              .clearAddress();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<IconButton>(find.byKey(const Key('copyHostIp')))
                .onPressed,
            isNull,
          );
          expect(
            _paintedTextColor(tester, find.byIcon(Icons.copy_outlined)),
            isNot(foreground),
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
