part of '../dashboard_screen.dart';

class _LibsTab extends StatefulWidget {
  const _LibsTab({required this.libs, this.extractNativeLibs});
  final List<String> libs;
  final bool? extractNativeLibs;

  @override
  State<_LibsTab> createState() => _LibsTabState();
}

class _LibsTabState extends State<_LibsTab> {
  String _query = '';
  Database? _db;
  bool _dbLoaded = false;

  @override
  void initState() {
    super.initState();
    _initDb();
  }

  Future<void> _initDb() async {
    try {
      final docDir = await getApplicationSupportDirectory();
      final dbFile = File('${docDir.path}/rules.db');

      // 自动检查：若本地可写目录无 rules.db，则从 assets 拷贝释放
      if (!dbFile.existsSync()) {
        final data = await rootBundle.load('assets/rules/rules.db');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await dbFile.writeAsBytes(bytes);
      }

      if (mounted) {
        setState(() {
          _db = sqlite3.open(dbFile.path);
          _dbLoaded = true;
        });
      }
    } catch (e) {
      print('初始化 rules.db 数据库错误: $e');
      if (mounted) {
        setState(() {
          _dbLoaded = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _db?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.libs.where((lib) {
      final parts = lib.split(':');
      final libName = parts[0];
      return libName.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '原生库数量: ${widget.libs.length}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                'extractNativeLibs: ${widget.extractNativeLibs != null ? widget.extractNativeLibs.toString() : "-"}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        _SearchField(
          onChanged: (val) => setState(() => _query = val),
          hint: '搜索 .so 动态库...',
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('无匹配原生库'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final libEntry = filtered[index];
                    final parts = libEntry.split(':');
                    final libName = parts[0];
                    final libSize = parts.length > 1
                        ? int.tryParse(parts[1])
                        : null;

                    final match = _matchKnownLib(libName);
                    return ListTile(
                      title: Text(libName),
                      subtitle: match != null
                          ? Text(
                              '${match['name']} (${match['desc']})',
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                              ),
                            )
                          : const Text('未知动态库', style: TextStyle(fontSize: 12)),
                      trailing: libSize != null && libSize > 0
                          ? Text(
                              _formatSize(libSize),
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                      leading: const Icon(
                        CupertinoIcons.square_stack_3d_up,
                        size: 20,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Map<String, String>? _matchKnownLib(String name) {
    final lower = name.toLowerCase();

    // 常用 native 库的 LibChecker-Rules 识别映射规则
    const rules = [
      _LibRule('flutter', 'Flutter Engine', 'Google 开发的跨平台 UI 框架底层 C++ 引擎库'),
      _LibRule('reactnative', 'React Native', 'Meta 开发的跨平台开发框架核心 C++ 运行库'),
      _LibRule('unity', 'Unity 3D', 'Unity Technologies 开发的 3D 游戏引擎底层核心库'),
      _LibRule('mono', 'Xamarin Mono', 'Microsoft 开发的跨平台 .NET 运行时引擎'),
      _LibRule('sgmain', '阿里聚安全 (Security Guard)', '阿里巴巴提供的移动应用安全防护与加密 SDK'),
      _LibRule(
        'sgsecuritybody',
        '阿里聚安全 (Security Guard)',
        '阿里巴巴提供的移动应用设备指纹与人机识别 SDK',
      ),
      _LibRule('bugly', '腾讯 Bugly', '腾讯提供的应用崩溃日志上报、异常监控与运营统计 SDK'),
      _LibRule('turing', '腾讯御安全 (Turing Shield)', '腾讯提供的应用安全加固、防逆向与防篡改 SDK'),
      _LibRule('amap', '高德地图 SDK', '高德提供的地图渲染、路线规划与导航核心引擎库'),
      _LibRule('co-amap', '高德地图 SDK', '高德提供的地图定位与混合定位核心库'),
      _LibRule('lbs', '百度地图 SDK', '百度提供的地图渲染、导航与定位服务核心库'),
      _LibRule('baidumapsdk', '百度地图 SDK', '百度提供的地图引擎核心 C++ 运行库'),
      _LibRule(
        'c++_shared',
        'Android NDK C++ Runtime',
        'Google 官方提供的 NDK 共享 C++ 标准库运行时 (libc++)',
      ),
      _LibRule('sqlite', 'SQLite Database', '轻量级嵌入式关系型数据库核心引擎库'),
      _LibRule(
        'realm-jni',
        'Realm Database',
        'MongoDB 提供的移动端跨平台 NoSQL 数据库核心 C++ 引擎库',
      ),
      _LibRule('ffmpeg', 'FFmpeg', '开源开源跨平台多媒体音视频解码、格式转换与处理库'),
      _LibRule('weibosdkcore', '新浪微博 SDK', '新浪微博官方提供的社交分享、登录与开放平台核心库'),
      _LibRule('jpush', '极光推送 (JPush)', '极光提供的移动端消息推送与实时通知交互 SDK'),
      _LibRule('getui', '个推 (GeTui)', '个推官方提供的消息推送、用户画像与数据分析 SDK'),
      _LibRule('tencentloc', '腾讯定位 SDK', '腾讯官方提供的混合定位与地理围栏服务 C++ 库'),
      _LibRule('msc', '科大讯飞语音 SDK', '科大讯飞官方提供的语音识别、语音合成与声纹唤醒核心库'),
      _LibRule(
        'v8',
        'V8 JavaScript Engine',
        'Google 开发的高性能开源 JavaScript 与 WebAssembly 引擎库',
      ),
      _LibRule(
        'xposed',
        'Xposed Framework',
        '基于劫持 Android 系统 Zygote 进程的 Hook 框架核心库',
      ),
      _LibRule('yuv', 'libyuv', 'Google 开源的 YUV 视频格式缩放、旋转与颜色转换核心库'),
      _LibRule('webrtc', 'WebRTC', '开源实时音视频通信 (RTC) 核心协议与渲染引擎库'),
      _LibRule('unwind', 'libunwind', '高效用于获取程序调用栈与进行 Crash 回溯的开源库'),
      _LibRule('crypto', 'OpenSSL (libcrypto)', '开源密码学算法与安全加密传输协议核心库'),
      _LibRule('ssl', 'OpenSSL (libssl)', '开源网络安全传输层协议 (SSL/TLS) 握手与通信库'),
      _LibRule('opencv', 'OpenCV', '开源跨平台计算机视觉与机器学习算法核心库'),
      _LibRule('pdfium', 'PDFium', 'Google 开源的 PDF 文档渲染、阅读与解析引擎库'),
      _LibRule(
        'gifimage',
        'GIF Image Decoder',
        'Facebook 提供的用于高效解码与渲染 GIF 动图的核心库',
      ),
      _LibRule('mp3lame', 'LAME MP3 Encoder', '高保真 MP3 音频格式压缩与编码开源库'),
      _LibRule('vlc', 'VLC Media Player', 'VideoLAN 开发的万能媒体播放器底层解码与渲染核心库'),
    ];

    for (final rule in rules) {
      if (lower.contains(rule.keyword)) {
        return {'name': rule.name, 'desc': rule.desc};
      }
    }

    // 2. 本地 SQLite 数据库查询
    if (_dbLoaded && _db != null) {
      try {
        final ResultSet results = _db!.select(
          'SELECT label FROM rules_table WHERE name = ? AND type = 0 LIMIT 1',
          [name],
        );
        if (results.isNotEmpty) {
          final row = results.first;
          final label = row['label'] as String?;
          if (label != null && label.isNotEmpty) {
            return {'name': label, 'desc': '规则库已识别'};
          }
        }
      } catch (e) {
        print('查询 SQLite 数据库失败: $e');
      }
    }

    return null;
  }
}

class _ComponentsTab extends StatefulWidget {
  const _ComponentsTab({
    required this.components,
    required this.hintText,
    this.isProvider = false,
  });

  final List<AdbComponentInfo> components;
  final String hintText;
  final bool isProvider;

  @override
  State<_ComponentsTab> createState() => _ComponentsTabState();
}

class _ComponentsTabState extends State<_ComponentsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.components
        .where(
          (c) =>
              c.name.toLowerCase().contains(_query.toLowerCase()) ||
              (c.authority != null &&
                  c.authority!.toLowerCase().contains(_query.toLowerCase())),
        )
        .toList();

    // 把 Exported == true 的组件置顶，第二排序依据是类名拼音字母
    filtered.sort((a, b) {
      if (a.exported && !b.exported) return -1;
      if (!a.exported && b.exported) return 1;
      return a.name.compareTo(b.name);
    });

    return Column(
      children: [
        _SearchField(
          onChanged: (val) => setState(() => _query = val),
          hint: widget.hintText,
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('无匹配组件'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final info = filtered[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        info.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.isProvider && info.authority != null)
                            Text(
                              'Authority: ${info.authority}',
                              style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 11,
                              ),
                            ),
                          if (info.permission != null)
                            Text(
                              'Required Permission: ${info.permission}',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      trailing: _ExportedBadge(exported: info.exported),
                      leading: Icon(
                        widget.isProvider
                            ? CupertinoIcons.share
                            : CupertinoIcons.gear_alt,
                        size: 16,
                      ),
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: info.name));
                        _showSnack(context, '已复制组件名称: ${info.name}');
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PermissionsTab extends ConsumerStatefulWidget {
  const _PermissionsTab({
    required this.deviceId,
    required this.packageName,
    required this.permissions,
  });

  final String deviceId;
  final String packageName;
  final List<AdbPermissionInfo> permissions;

  @override
  ConsumerState<_PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends ConsumerState<_PermissionsTab> {
  String _query = '';
  late List<AdbPermissionInfo> _perms;
  final Set<String> _toggling = {};

  @override
  void initState() {
    super.initState();
    _perms = List.from(widget.permissions);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _perms
        .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Column(
      children: [
        _SearchField(
          onChanged: (val) => setState(() => _query = val),
          hint: '搜索权限...',
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('无申请权限'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final perm = filtered[index];
                    final isToggling = _toggling.contains(perm.name);

                    return ListTile(
                      dense: true,
                      title: Text(
                        perm.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        perm.granted ? '已授予' : '未授予',
                        style: TextStyle(
                          color: perm.granted ? Colors.green : Colors.red,
                          fontSize: 11,
                        ),
                      ),
                      trailing: isToggling
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Switch(
                              value: perm.granted,
                              onChanged: (val) async {
                                setState(() => _toggling.add(perm.name));
                                final service = ref.read(
                                  appPermissionServiceProvider,
                                );
                                final result = val
                                    ? await service.grantPermission(
                                        widget.deviceId,
                                        widget.packageName,
                                        perm.name,
                                      )
                                    : await service.revokePermission(
                                        widget.deviceId,
                                        widget.packageName,
                                        perm.name,
                                      );

                                if (mounted) {
                                  setState(() {
                                    _toggling.remove(perm.name);
                                    if (result.isSuccess) {
                                      final i = _perms.indexWhere(
                                        (p) => p.name == perm.name,
                                      );
                                      if (i >= 0) {
                                        _perms[i] = AdbPermissionInfo(
                                          name: perm.name,
                                          granted: val,
                                        );
                                      }
                                    } else {
                                      _showSnack(
                                        context,
                                        '修改权限失败: ${result.message}',
                                        isError: true,
                                      );
                                    }
                                  });
                                }
                              },
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MetadataTab extends StatefulWidget {
  const _MetadataTab({required this.metadata});
  final Map<String, String> metadata;

  @override
  State<_MetadataTab> createState() => _MetadataTabState();
}

class _MetadataTabState extends State<_MetadataTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filteredKeys = widget.metadata.keys
        .where(
          (k) =>
              k.toLowerCase().contains(_query.toLowerCase()) ||
              widget.metadata[k]!.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();

    return Column(
      children: [
        _SearchField(
          onChanged: (val) => setState(() => _query = val),
          hint: '搜索元数据 Key / Value...',
        ),
        Expanded(
          child: filteredKeys.isEmpty
              ? const Center(child: Text('无匹配元数据'))
              : SelectionArea(
                  child: ListView.builder(
                    itemCount: filteredKeys.length,
                    itemBuilder: (context, index) {
                      final key = filteredKeys[index];
                      final val = widget.metadata[key];
                      return ListTile(
                        dense: true,
                        title: Text(
                          key,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(val ?? ''),
                        trailing: IconButton(
                          icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: '$key=$val'));
                            _showSnack(context, '已复制元数据键值对');
                          },
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _DexTab extends StatelessWidget {
  const _DexTab({required this.dexFiles});
  final List<AdbDexFileInfo> dexFiles;

  @override
  Widget build(BuildContext context) {
    final totalSize = dexFiles.fold<int>(0, (sum, f) => sum + f.size);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DEX 文件总数: ${dexFiles.length}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                'DEX 总大小: ${_formatSize(totalSize)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: dexFiles.isEmpty
              ? const Center(child: Text('没有检测到 DEX 文件'))
              : ListView.builder(
                  itemCount: dexFiles.length,
                  itemBuilder: (context, index) {
                    final f = dexFiles[index];
                    return ListTile(
                      dense: true,
                      title: Text(f.name),
                      trailing: Text(_formatSize(f.size)),
                      leading: const Icon(CupertinoIcons.doc_text, size: 18),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _LibRule {
  const _LibRule(this.keyword, this.name, this.desc);
  final String keyword;
  final String name;
  final String desc;
}

String _formatSize(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
  return '$bytes B';
}
