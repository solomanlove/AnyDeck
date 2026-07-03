part of '../dashboard_screen.dart';

/// 证书管理面板，方便用户导入用户 CA 证书或系统级 CA 证书。
class _CertificatePanel extends ConsumerWidget {
  const _CertificatePanel({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ActionCard(
      title: context.l10n.t('certManagerTitle'),
      children: [
        _ActionButton(
          icon: CupertinoIcons.person_crop_rectangle,
          label: context.l10n.t('importUserCert'),
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (context) => _UserCertImportDialog(deviceId: device.id),
            );
          },
        ),
        _ActionButton(
          icon: CupertinoIcons.shield,
          label: context.l10n.t('importSystemCert'),
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (context) =>
                  _SystemCertImportDialog(deviceId: device.id),
            );
          },
        ),
      ],
    );
  }
}
