# 已安装应用签名证书详情

## 功能边界

- 应用详情的“应用签名”Tab 展示当前 signer；Android 9（API 28）及以上存在证书轮换历史时，同时展示历史 signer。
- 每张 X.509 证书展示 Subject、Issuer、Serial Number、生效/失效时间、证书版本、签名算法、公钥算法，以及 MD5、SHA-1、SHA-256 指纹。
- `PackageManager` 返回的是 signer 证书和轮换历史，不能可靠判断 APK 使用 v1/v2/v3/v4 中哪些签名方案，因此页面不展示未经验证的签名方案字段。
- 应用列表继续使用原有 `signatureMd5` 字段，避免破坏缓存格式；详情新增 `signatures` 数组，旧版 Helper 未返回数组时 UI 回退到原有 MD5 展示。

## 数据链路

1. `AppManagementService.getPackageDetailedInfo()` 将 `package_icon_helper.dex` 推送到设备并通过 `app_process --details` 查询指定包。
2. `PackageIconHelper` 在 API 28+ 请求 `GET_SIGNING_CERTIFICATES`，旧系统继续使用 `GET_SIGNATURES`。
3. `PackageSignatureReader` 优先读取 `SigningInfo.getApkContentsSigners()`；单 signer 且存在密钥轮换时，再读取 `getSigningCertificateHistory()`。
4. Helper 将证书详情写入 JSON `signatures` 数组，`AdbPackageDetail.fromJson()` 解析为 `AdbSignatureInfo`。
5. `_SignatureTab` 按证书显示当前/历史状态，并提供每个指纹的独立复制入口。

## Helper JSON 字段

```json
{
  "signatureMd5": "001122...",
  "signatures": [
    {
      "current": true,
      "certificateVersion": 3,
      "serialNumber": "01AB",
      "subject": "CN=Example",
      "issuer": "CN=Example CA",
      "notBefore": 1704067200000,
      "notAfter": 2019686400000,
      "signatureAlgorithm": "SHA256withRSA",
      "publicKeyAlgorithm": "RSA",
      "md5": "...",
      "sha1": "...",
      "sha256": "..."
    }
  ]
}
```

时间字段使用 Unix epoch milliseconds，Dart UI 转换为本地时区显示。证书指纹在协议中保持小写无分隔符，UI 标准格式使用大写冒号分隔。

## DEX 构建与验证

Helper 源码变更后必须同时重新生成 `assets/android/package_icon_helper.dex`。当前构建基线为 Android 36 SDK、Java 8 bytecode、D8 `min-api 21`，输入至少包含：

```text
PackageIconHelper.java
PackageSignatureReader.java
```

验证范围：Java 源码已通过 `javac`，DEX 已通过 D8 生成并用 `dexdump` 确认包含两个 Helper class；Dart model 回归测试覆盖完整详情与旧 JSON 兼容。未启动 Flutter 项目，未执行真机证书展示验收。
