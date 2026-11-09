import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// 单设备 TLS 身份；密钥生成放到工作 Isolate，可保存以支持历史重连。
class ShareTlsIdentity {
  ShareTlsIdentity(this.certificate, this.privateKey);
  final String certificate;
  final String privateKey;

  static Future<ShareTlsIdentity> generate({bool persistent = false}) =>
      Isolate.run(() {
        final pair = CryptoUtils.generateEcKeyPair();
        final key = pair.privateKey as ECPrivateKey;
        final csr = X509Utils.generateEccCsrPem(
          {'CN': 'AnyDeck temporary device share'},
          key,
          pair.publicKey as ECPublicKey,
        );
        return ShareTlsIdentity(
          X509Utils.generateSelfSignedCertificate(
            key,
            csr,
            persistent ? 3650 : 1,
            notBefore: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
          CryptoUtils.encodeEcPrivateKeyToPem(key),
        );
      });

  String get fingerprint =>
      sha256.convert(CryptoUtils.getBytesFromPEMString(certificate)).toString();

  SecurityContext createContext() => SecurityContext(withTrustedRoots: false)
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2
    ..useCertificateChainBytes(utf8.encode(certificate))
    ..usePrivateKeyBytes(utf8.encode(privateKey));
}
