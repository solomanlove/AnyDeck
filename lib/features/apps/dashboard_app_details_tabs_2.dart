part of '../dashboard_screen.dart';

class _LibsTab extends StatefulWidget {
  const _LibsTab({required this.libs});
  final List<String> libs;

  @override
  State<_LibsTab> createState() => _LibsTabState();
}

class _LibsTabState extends State<_LibsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.libs
        .where((lib) => lib.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Column(
      children: [
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
                    final libName = filtered[index];
                    final match = _matchKnownLib(libName);
                    return ListTile(
                      title: Text(libName),
                      subtitle: match != null
                          ? Text(
                              '${match['name']} (${match['desc']})',
                              style: const TextStyle(color: Colors.green, fontSize: 12),
                            )
                          : const Text('未知动态库', style: TextStyle(fontSize: 12)),
                      leading: const Icon(CupertinoIcons.square_stack_3d_up, size: 20),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Map<String, String>? _matchKnownLib(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('flutter')) {
      return {'name': 'Flutter 引擎', 'desc': 'Flutter 跨平台框架底层核心 C++ 引擎库'};
    }
    if (lower.contains('reactnative')) {
      return {'name': 'React Native', 'desc': 'React Native 跨平台开发核心'};
    }
    if (lower.contains('unity')) {
      return {'name': 'Unity 3D', 'desc': 'Unity 3D 游戏引擎底层动态库'};
    }
    if (lower.contains('mono') || lower.contains('monodroid')) {
      return {'name': 'Xamarin Mono', 'desc': 'Xamarin 跨平台 .NET 运行时引擎'};
    }
    if (lower.contains('crypto') || lower.contains('ssl')) {
      return {'name': 'OpenSSL', 'desc': '加密与网络传输安全协议库'};
    }
    if (lower.contains('sqlite')) {
      return {'name': 'SQLite', 'desc': '嵌入式关系型数据库核心引擎'};
    }
    if (lower.contains('ffmpeg')) {
      return {'name': 'FFmpeg', 'desc': '音视频解码、处理底层引擎库'};
    }
    if (lower.contains('bugly')) {
      return {'name': '腾讯 Bugly', 'desc': '腾讯崩溃日志上报与运营统计 SDK'};
    }
    if (lower.contains('umeng')) {
      return {'name': '友盟统计', 'desc': '友盟移动数据分析与日志统计 SDK'};
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
        .where((c) =>
            c.name.toLowerCase().contains(_query.toLowerCase()) ||
            (c.authority != null && c.authority!.toLowerCase().contains(_query.toLowerCase())))
        .toList();

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
                      title: Text(info.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.isProvider && info.authority != null)
                            Text('Authority: ${info.authority}', style: const TextStyle(color: Colors.blue, fontSize: 11)),
                          if (info.permission != null)
                            Text('Required Permission: ${info.permission}', style: const TextStyle(color: Colors.red, fontSize: 11)),
                        ],
                      ),
                      trailing: _ExportedBadge(exported: info.exported),
                      leading: Icon(
                        widget.isProvider ? CupertinoIcons.share : CupertinoIcons.gear_alt,
                        size: 16,
                      ),
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
                      title: Text(perm.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(perm.granted ? '已授予' : '未授予', style: TextStyle(color: perm.granted ? Colors.green : Colors.red, fontSize: 11)),
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
                                final service = ref.read(appPermissionServiceProvider);
                                final result = val
                                    ? await service.grantPermission(widget.deviceId, widget.packageName, perm.name)
                                    : await service.revokePermission(widget.deviceId, widget.packageName, perm.name);

                                if (mounted) {
                                  setState(() {
                                    _toggling.remove(perm.name);
                                    if (result.isSuccess) {
                                      final i = _perms.indexWhere((p) => p.name == perm.name);
                                      if (i >= 0) {
                                        _perms[i] = AdbPermissionInfo(name: perm.name, granted: val);
                                      }
                                    } else {
                                      _showSnack(context, '修改权限失败: ${result.message}', isError: true);
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
        .where((k) =>
            k.toLowerCase().contains(_query.toLowerCase()) ||
            widget.metadata[k]!.toLowerCase().contains(_query.toLowerCase()))
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
                        title: Text(key, style: const TextStyle(fontWeight: FontWeight.bold)),
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
    String formatSize(int bytes) {
      const kb = 1024;
      const mb = kb * 1024;
      if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
      if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
      return '$bytes B';
    }

    final totalSize = dexFiles.fold<int>(0, (sum, f) => sum + f.size);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('DEX 文件总数: ${dexFiles.length}', style: const TextStyle(fontSize: 12)),
              Text('DEX 总大小: ${formatSize(totalSize)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                      trailing: Text(formatSize(f.size)),
                      leading: const Icon(CupertinoIcons.doc_text, size: 18),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
