part of '../dashboard_screen.dart';

/// 展示 Android 应用的签名证书、证书指纹与 X.509 详情。
class _SignatureTab extends StatelessWidget {
  const _SignatureTab({required this.signatureMd5, required this.signatures});

  /// 兼容旧版设备端 Helper 返回的首张证书 MD5。
  final String signatureMd5;
  final List<AdbSignatureInfo> signatures;

  @override
  Widget build(BuildContext context) {
    if (signatureMd5.isEmpty && signatures.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.info, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              context.l10n.t('noSignatureInfo'),
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBackground = isDark
        ? Colors.white.withValues(alpha: 0.02)
        : Colors.black.withValues(alpha: 0.01);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);

    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (signatures.isEmpty)
              _LegacySignatureCard(
                signatureMd5: signatureMd5,
                backgroundColor: cardBackground,
                borderColor: cardBorder,
              )
            else
              for (var index = 0; index < signatures.length; index++) ...[
                _SignatureCertificateCard(
                  index: index,
                  signature: signatures[index],
                  backgroundColor: cardBackground,
                  borderColor: cardBorder,
                ),
                if (index < signatures.length - 1) const SizedBox(height: 16),
              ],
            const SizedBox(height: 24),
            _SignatureHelpCard(theme: theme),
          ],
        ),
      ),
    );
  }
}

/// 单张签名证书的身份、有效期、算法与指纹详情。
class _SignatureCertificateCard extends StatelessWidget {
  const _SignatureCertificateCard({
    required this.index,
    required this.signature,
    required this.backgroundColor,
    required this.borderColor,
  });

  final int index;
  final AdbSignatureInfo signature;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = signature.current
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final detailRows = <({String label, String value, bool monospace})>[
      (
        label: context.l10n.t('signatureSubject'),
        value: signature.subject,
        monospace: false,
      ),
      (
        label: context.l10n.t('signatureIssuer'),
        value: signature.issuer,
        monospace: false,
      ),
      (
        label: context.l10n.t('signatureSerialNumber'),
        value: signature.serialNumber,
        monospace: true,
      ),
      (
        label: context.l10n.t('signatureValidFrom'),
        value: _formatSignatureDate(signature.notBefore),
        monospace: false,
      ),
      (
        label: context.l10n.t('signatureValidTo'),
        value: _formatSignatureDate(signature.notAfter),
        monospace: false,
      ),
      (
        label: context.l10n.t('signatureCertificateVersion'),
        value: signature.certificateVersion <= 0
            ? ''
            : 'X.509 v${signature.certificateVersion}',
        monospace: false,
      ),
      (
        label: context.l10n.t('signatureAlgorithm'),
        value: signature.signatureAlgorithm,
        monospace: true,
      ),
      (
        label: context.l10n.t('signaturePublicKeyAlgorithm'),
        value: signature.publicKeyAlgorithm,
        monospace: true,
      ),
    ].where((row) => row.value.isNotEmpty).toList();

    final fingerprints = <({String label, String value, bool raw})>[
      (label: 'MD5', value: signature.md5, raw: false),
      (label: 'SHA-1', value: signature.sha1, raw: false),
      (label: 'SHA-256', value: signature.sha256, raw: false),
      (
        label: context.l10n.t('signatureMd5Raw'),
        value: signature.md5,
        raw: true,
      ),
    ].where((row) => row.value.isNotEmpty).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${context.l10n.t('signatureCertificate')} ${index + 1}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  context.l10n.t(
                    signature.current
                        ? 'signatureCurrentSigner'
                        : 'signaturePastSigner',
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (detailRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: borderColor),
            const SizedBox(height: 4),
            for (final row in detailRows)
              _SignatureDetailRow(
                label: row.label,
                value: row.value,
                monospace: row.monospace,
              ),
          ],
          if (fingerprints.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              context.l10n.t('signatureFingerprints'),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            for (final fingerprint in fingerprints)
              _SignatureDetailRow(
                label: fingerprint.label,
                value: fingerprint.raw
                    ? fingerprint.value
                    : _formatSignatureFingerprint(fingerprint.value),
                monospace: true,
                copyable: true,
              ),
          ],
        ],
      ),
    );
  }
}

/// 证书属性行；长 DN 和 SHA-256 指纹允许换行且可独立复制。
class _SignatureDetailRow extends StatelessWidget {
  const _SignatureDetailRow({
    required this.label,
    required this.value,
    required this.monospace,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool monospace;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 136,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: monospace ? 'monospace' : null,
                height: 1.45,
                fontWeight: monospace ? FontWeight.w500 : null,
              ),
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.l10n.t('copySignatureValue'),
              icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                _showSnack(
                  context,
                  context.l10n.t('copySignatureValueSuccess'),
                );
              },
              style: IconButton.styleFrom(
                minimumSize: const Size.square(28),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 兼容旧 Helper 输出，避免升级过程中暂时丢失原有 MD5 展示。
class _LegacySignatureCard extends StatelessWidget {
  const _LegacySignatureCard({
    required this.signatureMd5,
    required this.backgroundColor,
    required this.borderColor,
  });

  final String signatureMd5;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SignatureDetailRow(
            label: context.l10n.t('signatureMd5'),
            value: _formatSignatureFingerprint(signatureMd5),
            monospace: true,
            copyable: true,
          ),
          _SignatureDetailRow(
            label: context.l10n.t('signatureMd5Raw'),
            value: signatureMd5,
            monospace: true,
            copyable: true,
          ),
        ],
      ),
    );
  }
}

class _SignatureHelpCard extends StatelessWidget {
  const _SignatureHelpCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.info_circle,
                size: 16,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.t('signatureHelpTitle'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.t('signatureHelpContent'),
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.5,
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatSignatureFingerprint(String raw) {
  if (raw.isEmpty ||
      raw.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(raw)) {
    return raw;
  }
  return [
    for (var index = 0; index < raw.length; index += 2)
      raw.substring(index, index + 2).toUpperCase(),
  ].join(':');
}

String _formatSignatureDate(int milliseconds) {
  if (milliseconds <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)} '
      '${twoDigits(date.hour)}:${twoDigits(date.minute)}:${twoDigits(date.second)}';
}
