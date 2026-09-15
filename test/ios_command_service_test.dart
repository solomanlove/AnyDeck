import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/features/ios/ios_syslog_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IosCommandService parser', () {
    test('parses app map and ignores go-ios log lines', () {
      const output = '''
{"time":"2026-09-07","level":"WARN","msg":"agent is not running"}
{"com.example.demo":{"CFBundleIdentifier":"com.example.demo","CFBundleDisplayName":"Demo","CFBundleShortVersionString":"1.2.3","ApplicationType":"User"},"com.apple.Preferences":{"CFBundleIdentifier":"com.apple.Preferences","CFBundleName":"Settings","CFBundleVersion":"100","ApplicationType":"System"}}
''';

      final apps = IosCommandService.parseApps(output);

      expect(apps, hasLength(2));
      expect(apps.first.name, 'Demo');
      expect(apps.first.bundleId, 'com.example.demo');
      expect(apps.first.version, '1.2.3');
      expect(apps.last.system, isTrue);
    });

    test('parses process objects and name-to-pid maps', () {
      const objectOutput =
          '{"processes":[{"pid":123,"name":"Demo"},{"ProcessIdentifier":"456","ExecutableName":"Runner"}]}';
      const mapOutput = '{"SpringBoard":42,"Demo":99}';

      final objectProcesses = IosCommandService.parseProcesses(objectOutput);
      final mapProcesses = IosCommandService.parseProcesses(mapOutput);

      expect(objectProcesses.map((item) => item.pid), containsAll([123, 456]));
      expect(mapProcesses.map((item) => item.pid), containsAll([42, 99]));
      expect(mapProcesses.firstWhere((item) => item.pid == 99).name, 'Demo');
    });

    test('IosSyslogTab.formatSyslogLine parses json log lines properly', () {
      const jsonLine =
          '{"timestamp":"2026-09-15T10:53:52","device":"zhangshijiedeiPhone","process":"mDNSResponder","pid":"111","level":"Notice","message":"<private>"}';
      final formatted = IosSyslogTab.formatSyslogLine(jsonLine);
      expect(formatted, '[10:53:52] [Notice] mDNSResponder(111): <private>');

      const plainLine = 'Regular raw syslog text';
      expect(IosSyslogTab.formatSyslogLine(plainLine), plainLine);

      const warnJson = '{"time":"2026-09-15","level":"WARN","msg":"daemon inactive"}';
      expect(IosSyslogTab.formatSyslogLine(warnJson), '[WARN] daemon inactive');
    });
  });
}
