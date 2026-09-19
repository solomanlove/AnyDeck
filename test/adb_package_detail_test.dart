import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/apps/adb_package_detail.dart';

void main() {
  test('签名证书详情可从 Helper JSON 解析并保持序列化字段', () {
    final detail = AdbPackageDetail.fromJson({
      'packageName': 'com.example.app',
      'signatureMd5': '00112233445566778899aabbccddeeff',
      'signatures': [
        {
          'current': true,
          'certificateVersion': 3,
          'serialNumber': '01AB',
          'subject': 'CN=Example',
          'issuer': 'CN=Example CA',
          'notBefore': 1704067200000,
          'notAfter': 2019686400000,
          'signatureAlgorithm': 'SHA256withRSA',
          'publicKeyAlgorithm': 'RSA',
          'md5': '00112233445566778899aabbccddeeff',
          'sha1': '00112233445566778899aabbccddeeff00112233',
          'sha256':
              '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
        },
      ],
    });

    expect(detail.signatures, hasLength(1));
    expect(detail.signatures.single.current, isTrue);
    expect(detail.signatures.single.subject, 'CN=Example');
    expect(detail.signatures.single.signatureAlgorithm, 'SHA256withRSA');
    expect(
      (detail.toJson()['signatures'] as List).single,
      containsPair('sha256', detail.signatures.single.sha256),
    );
  });

  test('旧版 Helper 未返回证书数组时保持 MD5 兼容', () {
    final detail = AdbPackageDetail.fromJson({
      'packageName': 'com.example.legacy',
      'signatureMd5': 'ffeeddccbbaa99887766554433221100',
    });

    expect(detail.signatureMd5, 'ffeeddccbbaa99887766554433221100');
    expect(detail.signatures, isEmpty);
  });
}
