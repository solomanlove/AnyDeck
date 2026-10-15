import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/harmony/hdc_service_fport.dart';
import 'package:any_deck/core/providers/network_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filterReverseOnly', () {
    test('从 fport ls 输出中只保留 [Reverse] 条目并去掉标注', () {
      const raw = '''
192.168.31.83:5555    tcp:1234 localabstract:webview_devtools_remote_1234    [Forward]
192.168.31.83:5555    tcp:8788 tcp:8788    [Reverse]
192.168.31.83:5555    tcp:8081 tcp:8080    [Reverse]
''';
      final filtered = HdcServiceFport.filterReverseOnly(raw);
      expect(filtered, 'tcp:8788 tcp:8788\ntcp:8081 tcp:8080');
    });

    test('只有正向转发时返回空字符串', () {
      const raw = '''
192.168.31.83:5555    tcp:1234 localabstract:xxx    [Forward]
''';
      expect(HdcServiceFport.filterReverseOnly(raw), isEmpty);
    });

    test('无任何转发时返回空字符串', () {
      expect(HdcServiceFport.filterReverseOnly(''), isEmpty);
    });
  });

  group('parseReverseList', () {
    test('解析鸿蒙过滤后的反向转发 stdout', () {
      final list = parseReverseList('tcp:8788 tcp:8788\ntcp:8081 tcp:8080');
      expect(list.length, 2);
      expect(list[0].devicePort, 'tcp:8788');
      expect(list[0].localPort, 'tcp:8788');
      expect(list[1].devicePort, 'tcp:8081');
      expect(list[1].localPort, 'tcp:8080');
    });

    test('兼容安卓 adb reverse --list 格式', () {
      final list = parseReverseList('ABC123 tcp:8081 tcp:8080');
      expect(list.length, 1);
      expect(list[0].devicePort, 'tcp:8081');
      expect(list[0].localPort, 'tcp:8080');
    });

    test('forward 的 localabstract 行不会被误解析', () {
      final list = parseReverseList(
        '192.168.31.83:5555 tcp:1234 localabstract:webview_devtools_remote',
      );
      expect(list, isEmpty);
    });
  });
}