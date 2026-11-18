part of '../dashboard_screen.dart';

/// 设备列表面板入口，只保留排序状态，具体 UI 拆到 extension 中维护。
class _DeviceListPanel extends ConsumerStatefulWidget {
  const _DeviceListPanel();

  @override
  ConsumerState<_DeviceListPanel> createState() => _DeviceListPanelState();
}

class _DeviceListPanelState extends ConsumerState<_DeviceListPanel> {
  final _searchController = TextEditingController();
  String _query = '';
  DeviceStatusFilter _filter = DeviceStatusFilter.all;
  String? _groupId;
  DeviceViewMode _viewMode = DeviceViewMode.wall;
  bool _batchMode = false;
  String _sortColumn = 'id';
  bool _sortAscending = true;
  String? _contextDeviceId;
  bool _deviceContextMenuOpen = false;
  bool _deviceQuickActionRunning = false;

  /// 右键选中只更新行高亮，不切换主窗口 Route 或改变批量勾选。
  void _selectContextDevice(String deviceId) =>
      setState(() => _contextDeviceId = deviceId);

  void _setDeviceQuickActionRunning(bool running) =>
      setState(() => _deviceQuickActionRunning = running);

  void _changeQuery(String value) => setState(() => _query = value);
  void _changeFilter(DeviceStatusFilter value) =>
      setState(() => _filter = value);
  void _changeGroup(String? value) => setState(() => _groupId = value);
  void _changeViewMode(DeviceViewMode value) =>
      setState(() => _viewMode = value);

  /// 空结果清除搜索、状态与分组筛选，保留当前布局和批量选择。
  void _resetDeviceFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _filter = DeviceStatusFilter.all;
      _groupId = null;
    });
  }

  /// 仅补全已保存成员的物理身份；后台失败保留旧数据，后续刷新可重试。
  void _synchronizeDeviceGroups(List<RegisteredDevice> devices) {
    unawaited(
      ref.read(deviceGroupsProvider.notifier)
          .synchronizeDevices(devices).catchError((Object _) {}),
    );
  }

  /// 退出批量管理时清除注册表勾选，切换视图和筛选则保留选择。
  void _changeBatchMode(bool value) {
    if (!value) {
      final registry = ref.read(deviceRegistryProvider.notifier);
      for (final device in ref.read(deviceRegistryProvider)) {
        if (device.isChecked) registry.toggleCheck(device.id);
      }
    }
    setState(() => _batchMode = value);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) => _buildDeviceListPanel(context);
}
