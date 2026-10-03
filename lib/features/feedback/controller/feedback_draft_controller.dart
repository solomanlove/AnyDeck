import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../model/feedback_environment.dart';
import '../model/github_feedback.dart';

/// 读取已有设备注册表，不额外发送 ADB/HDC 命令或监听设备变化。
final feedbackEnvironmentProvider = Provider.autoDispose<FeedbackEnvironment>((
  ref,
) {
  final selected = ref.read(selectedDeviceProvider);
  final devices = ref.read(deviceRegistryProvider);
  return FeedbackEnvironment.capture(
    FeedbackEnvironment.selectDevice(devices, selected?.id),
  );
});

/// 弹窗内独立草稿控制器，两种反馈分别持有标题与正文，关闭时统一释放。
class FeedbackDraftController extends ChangeNotifier {
  FeedbackDraftController(
    AppLocalizations l10n,
    FeedbackEnvironment environment,
  ) {
    for (final kind in FeedbackKind.values) {
      _titles[kind] = TextEditingController()..addListener(notifyListeners);
      _bodies[kind] = TextEditingController(
        text: GithubFeedback.body(l10n, kind, environment.format(l10n)),
      )..addListener(notifyListeners);
    }
  }

  final _titles = <FeedbackKind, TextEditingController>{};
  final _bodies = <FeedbackKind, TextEditingController>{};
  FeedbackKind _kind = FeedbackKind.bug;

  FeedbackKind get kind => _kind;
  TextEditingController get title => _titles[_kind]!;
  TextEditingController get body => _bodies[_kind]!;
  bool get hasTitle => title.text.trim().isNotEmpty;

  Uri get fullUri =>
      GithubFeedback.newIssueUri(_kind, body.text, title: title.text.trim());

  /// 按编码后的 URL 长度判断，中文和特殊字符同样受保护；正文绝不截断。
  bool get needsBodyCopy => fullUri.toString().length > 6000;
  Uri get launchUri => needsBodyCopy
      ? GithubFeedback.newIssueUri(_kind, '', title: title.text.trim())
      : fullUri;

  void select(FeedbackKind kind) {
    if (_kind == kind) return;
    _kind = kind;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final controller in [..._titles.values, ..._bodies.values]) {
      controller.dispose();
    }
    super.dispose();
  }
}
