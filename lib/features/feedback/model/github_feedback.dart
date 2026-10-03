import '../../../app/l10n/app_localizations.dart';

/// 反馈类型只影响预填内容，不依赖远端模板或仓库标签权限。
enum FeedbackKind { bug, feature }

/// GitHub 反馈草稿：仅携带用户可预览的正文，不读取设备、日志或账号。
class GithubFeedback {
  const GithubFeedback._();

  static final issuesUri = Uri.https(
    'github.com',
    '/solomanlove/AnyDeck/issues',
  );

  static String body(
    AppLocalizations l10n,
    FeedbackKind kind,
    String hostSystem,
  ) => l10n
      .t(kind == FeedbackKind.bug ? 'feedbackBugBody' : 'feedbackFeatureBody')
      .replaceAll('{system}', hostSystem);

  /// 使用 URI 编码保留中文、换行和特殊符号，无需 GitHub API Token。
  static Uri newIssueUri(FeedbackKind kind, String body) => Uri.https(
    issuesUri.host,
    '${issuesUri.path}/new',
    {'title': kind == FeedbackKind.bug ? '[Bug] ' : '[Feature] ', 'body': body},
  );
}
