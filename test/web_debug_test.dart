import 'package:flutter_test/flutter_test.dart';
import 'package:adb_manage/core/web_debug/webpage_target.dart';

void main() {
  group('WebpageTarget Serialization & Parsing', () {
    test('fromJson and toJson are symmetrical', () {
      final json = {
        'id': 'BFDBA256BDE16CA5260CCBEAF3130F6C',
        'title': '北京环球度假区',
        'url': 'https://www.universalbeijingresort.com/',
        'type': 'page',
        'devtoolsFrontendUrl': 'https://chrome-devtools-frontend.appspot.com/serve_rev/@d1ef/inspector.html?ws=localhost:53123/devtools/page/BFDBA256BDE16CA5260CCBEAF3130F6C',
        'webSocketDebuggerUrl': 'ws://localhost:53123/devtools/page/BFDBA256BDE16CA5260CCBEAF3130F6C',
      };

      final target = WebpageTarget.fromJson(
        json: json,
        packageName: 'com.ubrmb.app',
        pid: '6131',
        socketName: 'webview_devtools_remote_6131',
        port: 53123,
      );

      expect(target.id, 'BFDBA256BDE16CA5260CCBEAF3130F6C');
      expect(target.title, '北京环球度假区');
      expect(target.url, 'https://www.universalbeijingresort.com/');
      expect(target.type, 'page');
      expect(target.packageName, 'com.ubrmb.app');
      expect(target.pid, '6131');
      expect(target.socketName, 'webview_devtools_remote_6131');
      expect(target.port, 53123);
      expect(target.devtoolsFrontendUrl, json['devtoolsFrontendUrl']);
      expect(target.webSocketDebuggerUrl, json['webSocketDebuggerUrl']);

      final encoded = target.toJson();
      expect(encoded['id'], target.id);
      expect(encoded['title'], target.title);
      expect(encoded['url'], target.url);
      expect(encoded['type'], target.type);
      expect(encoded['packageName'], target.packageName);
      expect(encoded['pid'], target.pid);
      expect(encoded['socketName'], target.socketName);
      expect(encoded['port'], target.port);
    });

    test('fromJson handles null values and returns safe defaults', () {
      final json = <String, dynamic>{};
      final target = WebpageTarget.fromJson(
        json: json,
        packageName: 'com.example.app',
        pid: '1234',
        socketName: 'webview_devtools_remote_1234',
        port: 8080,
      );

      expect(target.id, '');
      expect(target.title, '');
      expect(target.url, '');
      expect(target.type, '');
      expect(target.devtoolsFrontendUrl, '');
      expect(target.webSocketDebuggerUrl, '');
    });
  });
}
