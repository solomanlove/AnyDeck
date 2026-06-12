# Skill: adb-cert-management (证书管理规范)

## 概述
本技能负责规范和处理如何向 Android 设备导入用户证书以及系统证书（Root 权限）。涉及不同 Android 版本的证书存储路径、权限控制及 host 端的证书哈希计算。

## 典型操作模式

### 1. 导入用户证书 (User Certificate)
用户凭证和 CA 证书导入手机，无需 Root，但需要用户在设备上手动确认。
- **存储路径**: 优先上传至 `/sdcard/Download/<filename>` (确保写入权限)。
- **MimeType 匹配**:
  - `.p12` / `.pfx`: `application/x-pkcs12`
  - `.pem` / `.der` / `.crt` / `.cer`: `application/x-x509-ca-cert`
- **调起指令**:
  ```bash
  adb shell am start -n com.android.certinstaller/.CertInstallerMain -a android.intent.action.VIEW -t <MimeType> -d file:///sdcard/Download/<filename>
  ```
- **降级指南**: Android 11+ 起，系统限制了凭证的自动安装。如果 Intent 未能自动弹出，需提示用户手动到 “设置 -> 安全 -> 更多安全设置 -> 加密与凭据 -> 从存储设备安装 -> CA 证书” 选择该文件。

### 2. 导入系统证书 (System Certificate - 需 Root)
为了系统级信任（例如截获 HTTPS 流量），需要将 CA 证书安装到系统可信凭证目录。
- **证书哈希化命名**: Android 要求系统证书以 `Subject Hash` 命名，后缀为 `.0`。
- **Host 端哈希计算 (Openssl)**:
  - PEM 格式: `openssl x509 -inform PEM -subject_hash_old -in <file> -noout`
  - DER 格式: `openssl x509 -inform DER -subject_hash_old -in <file> -noout`
  - Windows 环境下如果 `openssl` 没在 PATH 中，可检索 Git / OpenSSL 默认安装路径。如果均不可用，应提供 UI 文本框供用户手动录入。
- **Android 系统适配脚本**:
  - Android 9 及以下: 重新挂载 `/system` 为读写并拷贝证书：
    ```bash
    mount -o rw,remount /system
    cp -f /data/local/tmp/<hash>.0 /system/etc/security/cacerts/
    chmod 644 /system/etc/security/cacerts/<hash>.0
    ```
  - Android 10+ (API >= 29): 由于 `/system` 彻底只读，使用 `tmpfs` 内存临时挂载覆盖目录（重启后失效）：
    ```bash
    mkdir -p /data/local/tmp/cacerts
    cp -f /system/etc/security/cacerts/* /data/local/tmp/cacerts/
    cp -f /data/local/tmp/<hash>.0 /data/local/tmp/cacerts/
    chown root:root /data/local/tmp/cacerts/*
    chmod 644 /data/local/tmp/cacerts/*
    mount -t tmpfs tmpfs /system/etc/security/cacerts
    cp -f /data/local/tmp/cacerts/* /system/etc/security/cacerts/
    ```
  - Android 14+ (API >= 34): 额外需要通过 `nsenter` 绑定挂载 Conscrypt APEX 目录：
    ```bash
    nsenter --mount=/proc/1/ns/mnt mount --bind /system/etc/security/cacerts /apex/com.android.conscrypt/cacerts
    ```
- **执行方式**:
  建议将上述逻辑动态生成并写入手机端脚本 `/data/local/tmp/install_cert.sh`，然后通过 `su -c "sh /data/local/tmp/install_cert.sh"` 执行，避免参数转义问题，最后用 `rm` 清理临时脚本与证书。
