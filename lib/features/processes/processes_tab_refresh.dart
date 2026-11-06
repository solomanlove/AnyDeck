part of 'processes_tab.dart';

/// 自动与手动刷新共用在途锁，保持 UI Loading 与请求互斥职责独立。
extension _ProcessesTabRefresh on _ProcessesTabState {
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    if (!widget.isVisible) return;
    final isOnline = ref.read(deviceOnlineProvider(widget.device.id));
    if (_autoRefresh && isOnline) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (mounted && !_refreshing) {
          final stillOnline = ref.read(deviceOnlineProvider(widget.device.id));
          if (stillOnline && widget.isVisible) {
            _refreshProcesses(silent: true);
          } else {
            _stopRefreshTimer();
          }
        }
      });
    }
  }

  void _stopRefreshTimer() {
    _refreshRevision++;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _toggleAutoRefresh(bool? value) {
    if (value == null) return;
    _updateRefreshUi(() {
      _autoRefresh = value;
      if (_autoRefresh) {
        _startRefreshTimer();
      } else {
        _stopRefreshTimer();
      }
    });
  }

  Future<void> _refreshProcesses({bool silent = false}) async {
    if (!widget.device.isOnline) {
      return;
    }
    if (_refreshing) return;
    // 互斥与 Loading 分离：静默刷新同样占用在途标记。
    _refreshing = true;
    if (!silent) _updateRefreshUi(() {});
    final deviceId = widget.device.id;
    final revision = _refreshRevision;
    try {
      ref.invalidate(processesProvider(deviceId));
      await ref.read(processesProvider(deviceId).future);
    } catch (e) {
      if (mounted && !silent && revision == _refreshRevision) {
        DashboardSnack.show(context, e.toString(), isError: true);
      }
    } finally {
      _refreshing = false;
      if (mounted && !silent) _updateRefreshUi(() {});
    }
  }
}
