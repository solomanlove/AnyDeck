part of '../dashboard_screen.dart';

/// 用户证书导入向导对话框。
class _UserCertImportDialog extends ConsumerStatefulWidget {
  const _UserCertImportDialog({required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<_UserCertImportDialog> createState() =>
      _UserCertImportDialogState();
}

class _UserCertImportDialogState extends ConsumerState<_UserCertImportDialog> {
  XFile? _selectedFile;
  bool _isInstalling = false;
  String? _statusMessage;
  bool _isSuccess = false;

  Future<void> _pickFile() async {
    const typeGroup = XTypeGroup(
      label: 'Certificates (*.cer, *.crt, *.pem, *.der, *.p12, *.pfx)',
      extensions: ['cer', 'crt', 'pem', 'der', 'p12', 'pfx'],
    );
    try {
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        setState(() {
          _selectedFile = file;
          _statusMessage = null;
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '选择文件出错: $e';
        _isSuccess = false;
      });
    }
  }

  Future<void> _install() async {
    if (_selectedFile == null) return;
    setState(() {
      _isInstalling = true;
      _statusMessage = '正在上传证书到手机...';
    });

    try {
      final adb = ref.read(adbServiceProvider);
      final localPath = _selectedFile!.path;
      final fileName = _selectedFile!.name;
      final remotePath = '/sdcard/Download/$fileName';

      // 1. 上传文件到手机的 Download 文件夹
      final pushRes = await adb.run([
        '-s',
        widget.deviceId,
        'push',
        localPath,
        remotePath,
      ]);

      if (!pushRes.isSuccess) {
        setState(() {
          _isInstalling = false;
          _isSuccess = false;
          _statusMessage = '上传失败: ${pushRes.stderr}';
        });
        return;
      }

      // 2. 调起系统的凭据安装器 intent
      setState(() {
        _statusMessage = '已上传，正在手机上调起证书安装界面...';
      });

      final nameLower = fileName.toLowerCase();
      final mimeType =
          (nameLower.endsWith('.p12') || nameLower.endsWith('.pfx'))
          ? 'application/x-pkcs12'
          : 'application/x-x509-ca-cert';

      await adb.shell(
        widget.deviceId,
        'am start -n com.android.certinstaller/.CertInstallerMain '
        '-a android.intent.action.VIEW '
        '-t $mimeType '
        '-d file://$remotePath',
      );

      setState(() {
        _isInstalling = false;
        _isSuccess = true;
        _statusMessage = context.l10n.t('certInstallStart');
      });
    } catch (e) {
      setState(() {
        _isInstalling = false;
        _isSuccess = false;
        _statusMessage = '安装出错: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(CupertinoIcons.person_crop_rectangle, size: 24),
          const SizedBox(width: 8),
          Text(context.l10n.t('certUserTitle')),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 第一步：选择证书文件
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.t('selectCertFile'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${context.l10n.t('certSupportedFormats')}.cer, .crt, .pem, .der, .p12, .pfx',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isInstalling ? null : _pickFile,
                          icon: const Icon(
                            CupertinoIcons.folder_open,
                            size: 16,
                          ),
                          label: Text(context.l10n.t('selectCertFile')),
                        ),
                      ],
                    ),
                    if (_selectedFile != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${context.l10n.t('selectedFile')}: ${_selectedFile!.name}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _selectedFile!.path,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 状态及反馈信息
            if (_statusMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isSuccess
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  border: Border.all(
                    color: _isSuccess ? Colors.green : Colors.red,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusMessage!,
                      style: TextStyle(
                        color: _isSuccess ? Colors.green : Colors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isSuccess) ...[
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.t('certUserGuide'),
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // 进度指示器
            if (_isInstalling) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isInstalling ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('cancel')),
        ),
        FilledButton.icon(
          onPressed: _selectedFile == null || _isInstalling ? null : _install,
          icon: const Icon(CupertinoIcons.cloud_upload_fill, size: 16),
          label: Text(context.l10n.t('certInstall')),
        ),
      ],
    );
  }
}

/// 系统证书导入向导对话框。
class _SystemCertImportDialog extends ConsumerStatefulWidget {
  const _SystemCertImportDialog({required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<_SystemCertImportDialog> createState() =>
      _SystemCertImportDialogState();
}

class _SystemCertImportDialogState
    extends ConsumerState<_SystemCertImportDialog> {
  XFile? _selectedFile;
  bool _isInstalling = false;
  String? _statusMessage;
  bool _isSuccess = false;

  final TextEditingController _hashController = TextEditingController();
  bool _showHashManualInput = false;
  bool _isCalculatingHash = false;

  @override
  void dispose() {
    _hashController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    const typeGroup = XTypeGroup(
      label: 'CA Certificates (*.cer, *.crt, *.pem, *.der)',
      extensions: ['cer', 'crt', 'pem', 'der'],
    );
    try {
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        setState(() {
          _selectedFile = file;
          _statusMessage = null;
          _isSuccess = false;
          _isCalculatingHash = true;
        });
        _autoCalculateHash(file.path);
      }
    } catch (e) {
      setState(() {
        _statusMessage = '选择文件出错: $e';
        _isSuccess = false;
      });
    }
  }

  Future<void> _autoCalculateHash(String path) async {
    final hash = await _calculateSubjectHash(path);
    if (mounted) {
      setState(() {
        _isCalculatingHash = false;
        if (hash != null) {
          _hashController.text = hash;
          _showHashManualInput = false;
        } else {
          _hashController.clear();
          _showHashManualInput = true;
          _statusMessage = '未能自动识别证书哈希，请手动输入哈希名称 (8位十六进制，例如 9a5ba575)。';
        }
      });
    }
  }

  /// 尝试使用本地 openssl 计算证书的旧版主题名称 MD5 哈希（例如 `9a5ba575`）
  Future<String?> _calculateSubjectHash(String filePath) async {
    // 1. 尝试以 PEM 格式计算
    try {
      final res = await Process.run('openssl', [
        'x509',
        '-inform',
        'PEM',
        '-subject_hash_old',
        '-in',
        filePath,
        '-noout',
      ]);
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        return res.stdout.toString().trim();
      }
    } catch (_) {}

    // 2. 尝试以 DER 格式计算
    try {
      final res = await Process.run('openssl', [
        'x509',
        '-inform',
        'DER',
        '-subject_hash_old',
        '-in',
        filePath,
        '-noout',
      ]);
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        return res.stdout.toString().trim();
      }
    } catch (_) {}

    // 3. 在 Windows 平台上，搜索 Git、OpenSSL 的默认安装路径
    if (Platform.isWindows) {
      final winPaths = [
        r'C:\Program Files\Git\usr\bin\openssl.exe',
        r'C:\Program Files (x86)\Git\usr\bin\openssl.exe',
        r'C:\Program Files\OpenSSL-Win64\bin\openssl.exe',
        r'C:\Program Files\OpenSSL-Win32\bin\openssl.exe',
      ];
      for (final path in winPaths) {
        if (await File(path).exists()) {
          for (final format in ['PEM', 'DER']) {
            try {
              final res = await Process.run(path, [
                'x509',
                '-inform',
                format,
                '-subject_hash_old',
                '-in',
                filePath,
                '-noout',
              ]);
              if (res.exitCode == 0 &&
                  res.stdout.toString().trim().isNotEmpty) {
                return res.stdout.toString().trim();
              }
            } catch (_) {}
          }
        }
      }
    }
    return null;
  }

  Future<void> _install() async {
    final hash = _hashController.text.trim().toLowerCase();
    if (_selectedFile == null || hash.isEmpty) return;

    if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(hash)) {
      setState(() {
        _statusMessage = '错误：哈希值必须是 8 位十六进制字符！';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isInstalling = true;
      _statusMessage = '正在准备临时文件夹...';
    });

    try {
      final adb = ref.read(adbServiceProvider);

      // 1. 将所选证书在本地拷贝到临时文件夹中，重命名为 <hash>.0
      final tempDir = await Directory.systemTemp.createTemp('adb_cert_');
      final localTempCert = File('${tempDir.path}/$hash.0');
      await File(_selectedFile!.path).copy(localTempCert.path);

      // 2. 将证书推送至手机的临时目录
      setState(() {
        _statusMessage = '正在上传证书文件至手机临时目录...';
      });
      final pushCertRes = await adb.run([
        '-s',
        widget.deviceId,
        'push',
        localTempCert.path,
        '/data/local/tmp/$hash.0',
      ]);

      if (!pushCertRes.isSuccess) {
        setState(() {
          _isInstalling = false;
          _isSuccess = false;
          _statusMessage = '推送证书文件失败: ${pushCertRes.stderr}';
        });
        return;
      }

      // 3. 构建并写入手机端安装脚本
      // Android 10+ (API >= 29) 的系统分区是 read-only，通过挂载内存 tmpfs Overlay 覆盖系统证书目录，
      // 并额外针对 Android 14+ / APEX Conscrypt 目录执行 bind 挂载。
      final script =
          '''
sdk_version=\$(getprop ro.build.version.sdk)
if [ "\$sdk_version" -ge 29 ]; then
  mkdir -p /data/local/tmp/cacerts
  cp -f /system/etc/security/cacerts/* /data/local/tmp/cacerts/
  cp -f /data/local/tmp/$hash.0 /data/local/tmp/cacerts/
  chown root:root /data/local/tmp/cacerts/*
  chmod 644 /data/local/tmp/cacerts/*
  mount -t tmpfs tmpfs /system/etc/security/cacerts
  cp -f /data/local/tmp/cacerts/* /system/etc/security/cacerts/
  if [ "\$sdk_version" -ge 34 ]; then
    nsenter --mount=/proc/1/ns/mnt mount --bind /system/etc/security/cacerts /apex/com.android.conscrypt/cacerts
  fi
else
  mount -o rw,remount /system
  cp -f /data/local/tmp/$hash.0 /system/etc/security/cacerts/
  chmod 644 /system/etc/security/cacerts/$hash.0
fi
''';

      final localScript = File('${tempDir.path}/install_cert.sh');
      await localScript.writeAsString(script);

      setState(() {
        _statusMessage = '正在传送安装脚本到手机...';
      });
      final pushScriptRes = await adb.run([
        '-s',
        widget.deviceId,
        'push',
        localScript.path,
        '/data/local/tmp/install_cert.sh',
      ]);

      if (!pushScriptRes.isSuccess) {
        setState(() {
          _isInstalling = false;
          _isSuccess = false;
          _statusMessage = '推送安装脚本失败: ${pushScriptRes.stderr}';
        });
        return;
      }

      // 4. 以 root 身份运行安装脚本
      setState(() {
        _statusMessage = '正在申请 Root 权限并执行证书导入...';
      });
      final execRes = await adb.shell(
        widget.deviceId,
        'su -c "sh /data/local/tmp/install_cert.sh"',
      );

      // 5. 立即清理手机端的临时文件
      await adb.shell(
        widget.deviceId,
        'rm -f /data/local/tmp/install_cert.sh /data/local/tmp/$hash.0',
      );

      // 清理电脑本地临时文件
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}

      if (execRes.isSuccess) {
        setState(() {
          _isInstalling = false;
          _isSuccess = true;
          _statusMessage = context.l10n.t('certSystemInstallSuccess');
        });
      } else {
        setState(() {
          _isInstalling = false;
          _isSuccess = false;
          final errorMsg = execRes.stderr.isNotEmpty
              ? execRes.stderr.trim()
              : execRes.stdout.trim();
          _statusMessage =
              '${context.l10n.t('certSystemInstallFailed')}$errorMsg';
        });
      }
    } catch (e) {
      setState(() {
        _isInstalling = false;
        _isSuccess = false;
        _statusMessage = '安装出错: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isRootAsync = ref.watch(isDeviceRootProvider(widget.deviceId));
    final isRoot = isRootAsync.value ?? false;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(CupertinoIcons.shield_fill, size: 24),
          const SizedBox(width: 8),
          Text(context.l10n.t('certSystemTitle')),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 未 Root 提示
            if (!isRoot && !isRootAsync.isLoading) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.t('certSystemNoRoot'),
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // 第一步：选择证书文件
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.t('selectCertFile'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${context.l10n.t('certSupportedFormats')}.cer, .crt, .pem, .der',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isInstalling ? null : _pickFile,
                          icon: const Icon(
                            CupertinoIcons.folder_open,
                            size: 16,
                          ),
                          label: Text(context.l10n.t('selectCertFile')),
                        ),
                      ],
                    ),
                    if (_selectedFile != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${context.l10n.t('selectedFile')}: ${_selectedFile!.name}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _selectedFile!.path,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 第二步：哈希计算
            if (_isCalculatingHash) ...[
              const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('正在自动计算证书主题哈希...'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else if (_selectedFile != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hashController,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: context.l10n.t('certSubjectHash'),
                        hintText: '8位十六进制 (如 9a5ba575)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showHashManualInput
                                ? CupertinoIcons.lock
                                : CupertinoIcons.pencil,
                            size: 16,
                          ),
                          onPressed: () {
                            setState(() {
                              _showHashManualInput = !_showHashManualInput;
                            });
                          },
                          tooltip: '手动修改哈希值',
                        ),
                      ),
                      readOnly: !_showHashManualInput,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_showHashManualInput) ...[
                Text(
                  context.l10n.t('certSystemHashTip'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
            // 状态反馈
            if (_statusMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isSuccess
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  border: Border.all(
                    color: _isSuccess ? Colors.green : Colors.red,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _isSuccess ? Colors.green : Colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_isInstalling) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isInstalling ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('cancel')),
        ),
        FilledButton.icon(
          onPressed: _selectedFile == null || _isInstalling || !isRoot
              ? null
              : _install,
          icon: const Icon(CupertinoIcons.shield_fill, size: 16),
          label: Text(context.l10n.t('certInstall')),
        ),
      ],
    );
  }
}
