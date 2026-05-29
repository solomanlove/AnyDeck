part of '../dashboard_screen.dart';

/// 设备列表面板入口，只保留排序状态，具体 UI 拆到 extension 中维护。
class _DeviceListPanel extends ConsumerStatefulWidget {
  const _DeviceListPanel();

  @override
  ConsumerState<_DeviceListPanel> createState() => _DeviceListPanelState();
}

class _DeviceListPanelState extends ConsumerState<_DeviceListPanel> {
  String _sortColumn = 'id';
  bool _sortAscending = true;

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
