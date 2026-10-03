import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/feedback/controller/feedback_draft_controller.dart';
import 'package:any_deck/features/feedback/model/feedback_environment.dart';
import 'package:any_deck/features/feedback/model/github_feedback.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const l10n = AppLocalizations(Locale('zh'));
  const device = RegisteredDevice(
    id: 'PRIVATE_SERIAL',
    serial: 'PRIVATE_SERIAL',
    status: 'device',
    isOnline: true,
    customName: 'PRIVATE_ALIAS',
    ipAddress: '192.168.1.2',
    connections: ['PRIVATE_SERIAL', '192.168.1.2:5555'],
    model: 'Pixel 9',
    androidVersion: 'Android 16 (API 36)',
  );

  test(
    'environment matches selected channel but omits identifiers and aliases',
    () {
      final selected = FeedbackEnvironment.selectDevice([
        device,
      ], '192.168.1.2:5555');
      final environment = FeedbackEnvironment.capture(selected);
      final body = environment.format(l10n);
      expect(body, contains('Pixel 9'));
      expect(body, contains('Android 16 (API 36)'));
      expect(body, contains('Wi-Fi / 网络'));
      for (final privateValue in [
        'PRIVATE_SERIAL',
        'PRIVATE_ALIAS',
        '192.168.1.2',
      ]) {
        expect(body, isNot(contains(privateValue)));
      }
    },
  );

  test('only a single online device is selected automatically', () {
    final offline = device.copyWith(id: 'offline', isOnline: false);
    final other = device.copyWith(
      id: 'other',
      serial: 'other',
      connections: ['other'],
    );
    expect(
      FeedbackEnvironment.selectDevice([device, offline], null),
      same(device),
    );
    expect(FeedbackEnvironment.selectDevice([device, other], null), isNull);
    expect(
      FeedbackEnvironment.selectDevice([device], 'missing-device'),
      isNull,
    );
    expect(FeedbackEnvironment.selectDevice([offline], null), isNull);
  });

  test(
    'missing model never falls back to serial and unknown fields stay editable',
    () {
      const unnamed = RegisteredDevice(
        id: 'PRIVATE_SERIAL',
        status: 'device',
        isOnline: true,
      );
      final text = FeedbackEnvironment.capture(unnamed).format(l10n);
      expect(text, isNot(contains('PRIVATE_SERIAL')));
      expect(text, contains(l10n.t('feedbackUnknown')));
    },
  );

  test(
    'drafts keep edits across type switches, including removed environment',
    () {
      final controller = FeedbackDraftController(
        l10n,
        FeedbackEnvironment.capture(device),
      );
      addTearDown(controller.dispose);
      controller.title.text = '  中文标题 & ?  ';
      controller.body.text = '用户删除了环境信息';
      controller.select(FeedbackKind.feature);
      expect(controller.title.text, isEmpty);
      expect(controller.body.text, contains('Pixel 9'));
      controller.title.text = '建议标题';
      controller.body.text = '建议正文';
      controller.select(FeedbackKind.bug);
      expect(controller.title.text, '  中文标题 & ?  ');
      expect(controller.fullUri.queryParameters['title'], '[Bug] 中文标题 & ?');
      expect(controller.body.text, '用户删除了环境信息');
      controller.select(FeedbackKind.feature);
      expect(controller.body.text, '建议正文');
    },
  );

  test(
    'long encoded body uses title-only link and retains full body for copying',
    () {
      final controller = FeedbackDraftController(
        l10n,
        FeedbackEnvironment.capture(null),
      );
      addTearDown(controller.dispose);
      controller.title.text = '长反馈';
      final longBody = List.filled(1500, '中文 & #\n').join();
      controller.body.text = longBody;
      expect(controller.needsBodyCopy, isTrue);
      expect(controller.launchUri.queryParameters['title'], '[Bug] 长反馈');
      expect(controller.launchUri.queryParameters['body'], isEmpty);
      expect(controller.body.text, longBody);
      controller.body.text = '缩短后的正文';
      expect(controller.needsBodyCopy, isFalse);
      expect(controller.launchUri.queryParameters['body'], '缩短后的正文');
    },
  );
}
