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
      if (libName.toLowerCase().contains(_query.toLowerCase())) {
        return true;
      }
      final match = _matchKnownLib(libName);
      if (match != null) {
        final label = match['name'] ?? '';
        if (label.toLowerCase().contains(_query.toLowerCase())) {
          return true;
        }
      }
      return false;
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
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      child: ListTile(
                        title: Row(
                          children: [
                            Flexible(child: Text(libName)),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(
                                CupertinoIcons.doc_on_doc,
                                size: 16,
                              ),
                              tooltip: context.l10n.t('copy'),
                              onPressed: () => _copyLibName(libName),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(32, 32),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                        subtitle: match != null
                            ? Text(
                                match['desc'] != null && match['desc']!.isNotEmpty
                                    ? '${match['name']} (${match['desc']})'
                                    : match['name']!,
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
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _copyLibName(String libName) async {
    await Clipboard.setData(ClipboardData(text: libName));
    if (mounted) {
      DashboardSnack.show(context, context.l10n.t('copySuccess'));
    }
  }

  Map<String, String>? _matchKnownLib(String name) {
    final lower = name.toLowerCase();

    // 常用 native 库的 LibChecker-Rules 识别映射规则
    for (final rule in _commonNativeLibraryRules) {
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
            return {'name': label, 'desc': ''};
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
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      child: ListTile(
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
                        onLongPress: () {
                          Clipboard.setData(ClipboardData(text: info.name));
                          _showSnack(context, '已复制组件名称: ${info.name}');
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

/// 详情页权限入口，操作状态统一由共享权限面板管理。
class _PermissionsTab extends StatelessWidget {
  const _PermissionsTab({
    required this.deviceId,
    required this.packageName,
    required this.permissions,
  });
  final String deviceId;
  final String packageName;
  final List<AdbPermissionInfo> permissions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: AppPermissionsPanel(deviceId: deviceId, packageName: packageName),
  );
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
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        child: ListTile(
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
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(f.name),
                        trailing: Text(_formatSize(f.size)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

String _formatSize(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
  return '$bytes B';
}
