import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ios/ios_icon_service.dart';
import '../../../core/ios/ios_mirror_service.dart';
import '../../../core/ios/ios_process_info.dart';
import '../../../core/ios/ios_process_service.dart';

/// 独立的设备会话可由测试替换，离页自动释放全部 CLI。
final iosProcessServiceProvider = Provider.autoDispose
    .family<IosProcessService, String>((ref, udid) {
      final service = IosProcessService(
        ref.read(iosCommandServiceProvider),
        udid,
      );
      ref.onDispose(service.close);
      return service;
    });

/// 页面快照保留最近成功数据；错误不清空列表。
class IosProcessesState {
  const IosProcessesState({
    this.items = const [],
    this.busy = false,
    this.autoRefresh = true,
    this.error,
    this.metadataError,
  });
  final List<IosProcessInfo> items;
  final bool busy;
  final bool autoRefresh;
  final String? error;
  final String? metadataError;
}

/// 3 秒轮询不重入；图标按首次遇到的宿主请求，失败不每轮重试。
class IosProcessesController extends Notifier<IosProcessesState> {
  IosProcessesController(this.udid);
  final String udid;
  late IosProcessService _service;
  Timer? _timer;
  final _icons = <String, String>{};
  final _attemptedIcons = <String>{};
  final _iconRequest = IosIconRequest();
  bool _active = true;
  bool _fetchingIcons = false;

  @override
  IosProcessesState build() {
    // watch 保持会话存活，最后一个监听者离开后 autoDispose 终止工作。
    _service = ref.watch(iosProcessServiceProvider(udid));
    void stop() {
      _active = false;
      _timer?.cancel();
      _iconRequest.cancel();
      _service.close();
    }

    ref.onDispose(stop);
    scheduleMicrotask(refresh);
    return const IosProcessesState();
  }

  bool get _alive => _active && ref.mounted;

  void setAutoRefresh(bool value) {
    state = IosProcessesState(
      items: state.items,
      busy: state.busy,
      autoRefresh: value,
      error: state.error,
      metadataError: state.metadataError,
    );
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_alive && state.autoRefresh && !state.busy) {
      _timer = Timer(const Duration(seconds: 3), refresh);
    }
  }

  Future<void> refresh({bool refreshApps = false}) async {
    if (!_alive || state.busy) return;
    _timer?.cancel();
    state = IosProcessesState(
      items: state.items,
      busy: true,
      autoRefresh: state.autoRefresh,
      metadataError: state.metadataError,
    );
    try {
      final items = await _service.read(refreshApps: refreshApps);
      if (!_alive) return;
      state = IosProcessesState(
        items: _withIcons(items),
        autoRefresh: state.autoRefresh,
        metadataError: _service.metadataError,
      );
      unawaited(_loadIcons());
    } catch (error) {
      if (!_alive) return;
      state = IosProcessesState(
        items: state.items,
        error: error.toString(),
        autoRefresh: state.autoRefresh,
        metadataError: state.metadataError,
      );
    } finally {
      if (_alive) _schedule();
    }
  }

  List<IosProcessInfo> _withIcons(List<IosProcessInfo> items) {
    final icons = ref.read(iosIconServiceProvider);
    return items.map((item) {
      final app = item.app;
      return app == null
          ? item
          : item.withApp(
              app.copyWith(
                iconPath:
                    _icons[app.bundleId] ??
                    icons.getCachedIconPath(udid, app.bundleId),
              ),
            );
    }).toList();
  }

  Future<void> _loadIcons() async {
    if (!_alive || _fetchingIcons) return;
    final ids = state.items
        .map((item) => item.app?.bundleId)
        .whereType<String>()
        .where((id) => !_attemptedIcons.contains(id))
        .toSet();
    if (ids.isEmpty) return;
    _attemptedIcons.addAll(ids);
    _fetchingIcons = true;
    try {
      _icons.addAll(
        await ref
            .read(iosIconServiceProvider)
            .fetchIcons(udid, ids.toList(), request: _iconRequest),
      );
      if (!_alive) return;
      state = IosProcessesState(
        items: _withIcons(state.items),
        busy: state.busy,
        autoRefresh: state.autoRefresh,
        error: state.error,
        metadataError: state.metadataError,
      );
    } catch (_) {
      // 图标增强失败不影响进程及其操作。
    } finally {
      _fetchingIcons = false;
    }
  }

  Future<void> kill(IosProcessInfo item) async {
    if (!_alive || state.busy) return;
    _timer?.cancel();
    state = IosProcessesState(
      items: state.items,
      busy: true,
      autoRefresh: state.autoRefresh,
      error: state.error,
      metadataError: state.metadataError,
    );
    try {
      await _service.kill(item);
    } finally {
      if (_alive) {
        state = IosProcessesState(
          items: state.items,
          autoRefresh: state.autoRefresh,
          error: state.error,
          metadataError: state.metadataError,
        );
        _schedule();
      }
    }
    if (_alive) await refresh();
  }
}

final iosProcessesProvider = NotifierProvider.autoDispose
    .family<IosProcessesController, IosProcessesState, String>(
      IosProcessesController.new,
    );
